#!/usr/bin/env python3
# Send UCS-2 SMS via /dev/smd11 (Quectel RM520N-GL)
# Usage: send_sms_ucs2.py <phone> <utf8_text>
# Exit 0 on success, 1 on failure.

import sys, os, time, re

DEV = "/dev/smd11"
DEBUG = os.environ.get("SMS_DEBUG", "") != ""

def log(msg):
    if DEBUG:
        sys.stderr.write("[sms_ucs2] %s\n" % msg)

def swap_nibbles(digits):
    out = ""
    for i in range(0, len(digits), 2):
        out += digits[i+1] + digits[i]
    return out

def smsc_to_pdu(smsc):
    if smsc.startswith("+"):
        smsc = smsc[1:]
    if len(smsc) % 2:
        smsc += "F"
    swapped = swap_nibbles(smsc)
    length = 1 + len(swapped) // 2   # 1 байт на тип адреса
    return "%02X" % length + "91" + swapped

def phone_to_pdu(number):
    if number.startswith("+"):
        number = number[1:]
    ndigits = len(number)
    if len(number) % 2:
        number += "F"
    swapped = swap_nibbles(number)
    return "%02X" % ndigits + "91" + swapped

def build_pdu(smsc, number, text):
    smsc_part = smsc_to_pdu(smsc)
    first_octet = "11"
    mr = "00"
    dest = phone_to_pdu(number)
    pid_dcs = "0008"
    vp = "AA"
    ud_bytes = text.encode("utf-16-be")
    udl = "%02X" % len(ud_bytes)
    ud_hex = ud_bytes.hex().upper()
    tpdu = first_octet + mr + dest + pid_dcs + vp + udl + ud_hex
    full = smsc_part + tpdu
    tp_len = len(tpdu) // 2
    return full, tp_len

def read_until(fd, needles, timeout=15):
    data = b""
    start = time.time()
    while time.time() - start < timeout:
        try:
            chunk = os.read(fd, 4096)
            if chunk:
                data += chunk
                for n in needles:
                    if n in data:
                        return data, n
        except BlockingIOError:
            pass
        except OSError:
            break
        time.sleep(0.2)
    return data, None

def send_at(fd, cmd, timeout=3):
    os.write(fd, (cmd + "\r").encode("ascii"))
    data, found = read_until(fd, [b"OK", b"ERROR", b"+CME ERROR", b"+CMS ERROR"], timeout=timeout)
    return data

def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: send_sms_ucs2.py <phone> <text>\n")
        sys.exit(2)
    phone = sys.argv[1]
    text = sys.argv[2].strip()

    try:
        fd = os.open(DEV, os.O_RDWR)
    except OSError as e:
        sys.stderr.write("open %s failed: %s\n" % (DEV, e))
        sys.exit(1)

    try:
        # 1. Get SMSC from modem
        os.write(fd, b"AT+CSCA?\r")
        time.sleep(1.0)
        data = b""
        start = time.time()
        while time.time() - start < 5:
            try:
                chunk = os.read(fd, 4096)
                if chunk:
                    data += chunk
                if b"OK" in data or b"ERROR" in data:
                    break
            except BlockingIOError:
                pass
            time.sleep(0.2)
        log("CSCA response: %r" % data)
        m = re.search(rb'\+CSCA:\s*"([^"]+)"', data)
        if not m:
            sys.stderr.write("could not read SMSC (AT+CSCA?)\n")
            sys.exit(1)
        smsc = m.group(1).decode("ascii")
        log("SMSC: %s" % smsc)

        # 2. Build PDU
        pdu, tp_len = build_pdu(smsc, phone, text)
        log("PDU: %s (tp_len=%d)" % (pdu, tp_len))

        # 3. PDU mode
        send_at(fd, "AT+CMGF=0", timeout=3)
        time.sleep(0.3)

        # 4. CMGS
        os.write(fd, ("AT+CMGS=%d\r" % tp_len).encode("ascii"))
        time.sleep(0.8)
        try:
            os.read(fd, 4096)
        except OSError:
            pass

        # 5. PDU + Ctrl+Z
        os.write(fd, (pdu + "\x1a").encode("ascii"))
        data, found = read_until(fd, [b"+CMGS", b"ERROR", b"+CMS ERROR"], timeout=20)
        log("CMGS response: %r" % data)

        if b"+CMGS" in data:
            m = re.search(rb'\+CMGS:\s*(\d+)', data)
            n = m.group(1).decode() if m else "?"
            print("sms sent sucessfully: %s" % n)
            sys.exit(0)
        else:
            m = re.search(rb'\+CMS ERROR:\s*(\d+)', data)
            if m:
                print("sms not sent, code: %s" % m.group(1).decode())
            else:
                print("sms not sent, no response from modem")
            sys.exit(1)
    finally:
        os.close(fd)

if __name__ == "__main__":
    main()