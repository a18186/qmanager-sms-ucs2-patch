# Technical details

## Why sms_tool can't do UCS-2

`sms_tool` in QManager is a bundled binary (patched to default to `/dev/smd11`).
Its `-c` flag is documented as `(for ussd, 0 - 7BIT, 2 - UCS2, default: detect)`
— USSD only. For SMS, the tool always:

1. Switches to text mode (`AT+CMGF=1`).
2. Sends the text with `AT+CMGS` and lets the modem pick the encoding from
   the current `AT+CSCS`. `CSCS` on RM520N-GL resets to `"GSM"` after each
   attach, so the modem uses GSM 7-bit and replaces everything outside
   that alphabet with `?`.
3. The tool's internal encoder is hard-coded — it doesn't call `iconv`, so
   `GCONV_PATH=/opt/lib/gconv` and Entware's `gconv-modules` don't help.

The only reliable fix is to build the PDU yourself.

## PDU format

An SMS-SUBMIT PDU for a text message with UCS-2 encoding looks like:

```
[SMSC-len][SMSC-type][SMSC-digits]  first-octet MR len recipient-type recipient-digits PID DCS VP UDL UD
```

For SMS-SUBMIT:

| Field | Value | Notes |
|---|---|---|
| first-octet | `11` | SMS-SUBMIT, no VP format, no UDH |
| MR | `00` | message reference, 0 = modem picks |
| recipient-len | hex | number of decimal digits |
| recipient-type | `91` | international |
| recipient-digits | hex | nibbles swapped, `F`-padded |
| PID | `00` | protocol id |
| **DCS** | **`08`** | **UCS-2** |
| VP | `AA` | 4-day validity |
| UDL | hex | bytes (not chars!) of UD |
| UD | UTF-16BE hex | `text.encode('utf-16-be').hex().upper()` |

SMSC part (example for МТС `+79168999100`):

```
07 91 97 61 98 99 01 F0
```

Note: the leading `91` (type of address) sits **before** the swapped digits.
A common mistake is to swap the whole string including `91` — that yields
`99 10 F0` and the modem replies `+CMS ERROR: 350`.

## The patch (minimal diff)

Two hunks:

### Hunk 1 — new function after `sms_locked()`

```sh
# --- Locked Python UCS-2 sender wrapper --------------------------------------
sms_python_locked() {
    _py_err="/tmp/qmanager_sms_py_err.$$"
    (
        flock_wait 9 10 || exit 2
        _py_out=$(/opt/bin/python3 /opt/bin/send_sms_ucs2.py "$1" "$2" 2>"$_py_err")
        _py_rc=$?
        if [ "$_py_rc" -eq 0 ]; then
            printf '%s' "$_py_out"
        else
            _py_err_clean=$(cat "$_py_err" 2>/dev/null)
            if [ -n "$_py_err_clean" ]; then
                printf '%s' "$_py_err_clean"
            else
                printf '%s' "$_py_out"
            fi
        fi
        rm -f "$_py_err"
        exit "$_py_rc"
    ) 9<"$LOCK_FILE"
}
```

### Hunk 2 — replace the send block in `action=send`

**Original:**

```sh
        result=$(sms_locked send "$PHONE" "$MESSAGE")
        sms_rc=$?
```

**Patched:**

```sh
        non_ascii=$(printf '%s' "$MESSAGE" | LC_ALL=C tr -d '\000-\177')
        if [ -n "$non_ascii" ]; then
            qlog_info "Non-ASCII detected — using Python UCS-2 sender"
            result=$(sms_python_locked "$PHONE" "$MESSAGE")
            sms_rc=$?
        else
            result=$(sms_locked send "$PHONE" "$MESSAGE")
            sms_rc=$?
        fi
```

Everything else in `sms.sh` stays the same. A ready-to-apply `.patch` file is in this repo at `docs/sms.sh.patch`.

## Why Python

- Native UTF-16BE: `text.encode('utf-16-be')` — no iconv, no locales, no
  `gconv-modules` required.
- `python3-light` from Entware is ~5 MB, comes with all needed stdlib.
- Easier to maintain than a shell PDU builder.

## Interaction with the QManager poller

`qmanager_poller` opens `/dev/smd11` every few seconds to send `AT+QENG="servingcell"`.
`open()` with `O_NONBLOCK` fails immediately with `EBUSY` if the poller holds the port.
The Python script therefore:

1. Opens `/dev/smd11` in blocking mode (`os.O_RDWR`) — this waits for
   the poller to release the port (1-3 s typical).
2. Switches the fd to non-blocking mode with `fcntl(F_SETFL, flags | O_NONBLOCK)`
   so subsequent reads use timeouts.
3. Serializes with the poller via the same `flock` on `/tmp/qmanager_at.lock`.

That means QManager's own `flock` gates the poller and `sms_tool`, and
our wrapper acquires the same lock before calling Python. Python doesn't
need to know about `flock` — the parent shell does it.

## Testing checklist

Verified on firmware `RM520NGLAAR01A06M4G` with an MTS (Russia) SIM:

- [x] Latin text via sms_tool path — works as before.
- [x] Cyrillic (Привет) — arrives correctly.
- [x] Greek (Γειά σου) — arrives correctly.
- [x] CJK (你好) — arrives correctly.
- [x] Emoji non-BMP (🚀🔥) — arrives correctly (surrogate pairs handled).
- [x] Mixed ASCII + Cyrillic + CJK — arrives correctly.
- [x] Poller continues during send — no data loss.
- [x] Incoming SMS still readable.

## Known limitations

- Multi-part messages (>70 chars) are not separately tested. The modem's
  `AT+CMGS` should fragment automatically when UDL exceeds the single-part
  limit, but this has not been verified end-to-end. For guaranteed delivery,
  keep messages ≤ 70 characters, or accept fragmentation risk.
- Concatenated SMS (UDH) is not implemented in the PDU builder — the
  script always emits a single SMS-SUBMIT with no UDH. Long messages
  depend on the modem's own segmentation behaviour.