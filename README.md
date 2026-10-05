# QManager SMS UCS-2 Patch

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Fixes Cyrillic (and any non-Latin) SMS sending in [QManager for Quectel RM520N-GL](https://github.com/dr-dolomite/QManager-RM520N).

---

## The problem

QManager's bundled `sms_tool` silently replaces every non-GSM character with `?`. Cyrillic, Greek, Arabic, emoji, CJK — all become `?????` in the delivered SMS.

- The `-c 2` flag is **USSD-only** — it does nothing for SMS.
- Setting `AT+CSCS="UCS2"` and `AT+CSMP=17,167,0,8` doesn't help — QManager resets them at attach, and even if they stuck, `sms_tool` still constructs the PDU in GSM 7-bit.
- `GCONV_PATH` and locales make no difference — `sms_tool` uses its own hardcoded encoder, not glibc's.
- Setting `gconv-modules` from Entware does fix `iconv` for other programs, but not `sms_tool`.

Confirmed on firmware `RM520NGLAAR01A06M4G` (SDXLEMUR platform).

## The fix

A small Python script (`send_sms_ucs2.py`) that:

1. Reads the SMSC number via `AT+CSCA?`.
2. Builds an SMS-SUBMIT PDU with **DCS = 08** (UCS-2).
3. Encodes the text as UTF-16BE.
4. Sends `AT+CMGF=0` + `AT+CMGS=<len>` + `<pdu>` + Ctrl-Z to `/dev/smd11`.

QManager's CGI endpoint `sms.sh` is patched to route **non-ASCII messages** through this script, while **pure-ASCII** messages still take the fast `sms_tool` path.

Both paths serialize against the same `/tmp/qmanager_at.lock` flock that the poller and `qcmd` use, so no conflicts.

Supports the full Unicode range — Cyrillic, Greek, CJK, Arabic, emoji,
and anything else that fits in UTF-16. Each non-ASCII message takes the
UCS-2 path and delivers as typed.

---

## Install

Requirements:
- Quectel RM520N-GL with QManager installed
- ADB access (USB)
- ADB platform tools on the PC
- Entware already installed (QManager does this automatically)

**Windows:** run `install.bat`. The installer will:
1. Install `python3-light` and `gconv-modules` via `opkg` (~7 MB download).
2. Push `send_sms_ucs2.py` to `/opt/bin/`.
3. Save the original `sms.sh` as `sms.sh.orig` (only on first install).
4. Push the patched `sms.sh` to QManager's CGI directory.
5. Verify syntax and restart `lighttpd`.

**Manual install:** see [docs/TECHNICAL.md](docs/TECHNICAL.md).

## Verify

Send a Cyrillic SMS via QManager → **SMS Center → New Message**.

Expected: SMS arrives as typed. In **System Logs** you'll see:

```
Non-ASCII detected — using Python UCS-2 sender
```

## Uninstall

Run `uninstall.bat`. It restores `sms.sh` from the original (either from the local package or from `sms.sh.orig` on the modem) and removes the Python script. The Entware packages are left in place (they take almost no space).

---

## Compatibility

| Firmware | Status |
|---|---|
| RM520NGLAAR01A06M4G | ✅ tested |
| Other RM520N-GL revisions | likely works, not tested |

The patch assumes:
- `/dev/smd11` exists and is writable (standard for SDXLEMUR-based Quectel).
- Entware is at `/opt/`.
- QManager v0.1.16 or newer (uses the same `sms.sh` structure).

---

## Contributing upstream

This patch is a workaround, not a proper fix. If you maintain QManager
and want to fold the UCS-2 handling into the tool itself, the minimal
diff is in [docs/sms.sh.patch](docs/sms.sh.patch). The core change is:

- ~27 lines of shell (a new `sms_python_locked()` wrapper).
- ~130 lines of Python (PDU builder + serial I/O).

The cleaner long-term fix would be to extend `sms_tool` itself with
proper UCS-2 PDU construction. Its current encoder hard-codes GSM 7-bit
and ignores `DCS=08` regardless of locale or `GCONV_PATH`.

Discussion: [issue link / your repo link]

## License

MIT. Do whatever.