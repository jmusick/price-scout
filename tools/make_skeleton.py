"""Write a minimal AS3 SWF whose document class is an empty MovieClip subclass.

JPEXS (ffdec-cli -importScript) then compiles the real class from src/ into it,
so the project builds with no Flex SDK.

Usage: python -I tools/make_skeleton.py <out.swf> <ClassName>
"""

import struct
import sys

SWF_VERSION = 19
STAGE_W, STAGE_H = 1920, 1080
FRAME_RATE = 30

# Base classes of flash.display.MovieClip, outermost first, for the script's scope chain.
BASES = [
    ("", "Object"),
    ("flash.events", "EventDispatcher"),
    ("flash.display", "DisplayObject"),
    ("flash.display", "InteractiveObject"),
    ("flash.display", "DisplayObjectContainer"),
    ("flash.display", "Sprite"),
    ("flash.display", "MovieClip"),
]


def u30(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def abc_for(class_name):
    strings = [""]  # index 0 is implicit; real entries start at 1
    namespaces = [None]
    multinames = [None]

    def s(text):
        if text not in strings:
            strings.append(text)
        return strings.index(text)

    def ns(package):
        key = (0x16, s(package))
        if key not in namespaces:
            namespaces.append(key)
        return namespaces.index(key)

    def qname(package, name):
        key = (0x07, ns(package), s(name))
        if key not in multinames:
            multinames.append(key)
        return multinames.index(key)

    own = qname("", class_name)
    base_names = [qname(p, n) for p, n in BASES]
    movieclip = base_names[-1]

    pool = bytearray()
    pool += u30(0) + u30(0) + u30(0)  # int, uint, double pools
    pool += u30(len(strings))
    for text in strings[1:]:
        raw = text.encode("utf-8")
        pool += u30(len(raw)) + raw
    pool += u30(len(namespaces))
    for kind, name in namespaces[1:]:
        pool += bytes([kind]) + u30(name)
    pool += u30(0)  # ns sets
    pool += u30(len(multinames))
    for kind, namespace, name in multinames[1:]:
        pool += bytes([kind]) + u30(namespace) + u30(name)

    abc = bytearray(struct.pack("<HH", 16, 46)) + pool
    abc += u30(3)  # methods: 0 iinit, 1 cinit, 2 script init
    for _ in range(3):
        abc += u30(0) + u30(0) + u30(0) + b"\x00"
    abc += u30(0)  # metadata
    abc += u30(1)  # classes
    abc += u30(own) + u30(movieclip) + b"\x01" + u30(0) + u30(0) + u30(0)  # instance_info
    abc += u30(1) + u30(0)  # class_info: cinit, no traits
    abc += u30(1)  # scripts
    abc += u30(2) + u30(1) + u30(own) + b"\x04" + u30(1) + u30(0)  # class trait in slot 1

    def body(method, max_stack, max_scope, code):
        return (u30(method) + u30(max_stack) + u30(1) + u30(0) + u30(max_scope)
                + u30(len(code)) + bytes(code) + u30(0) + u30(0))

    iinit = [0xD0, 0x30, 0xD0, 0x49, 0x00, 0x47]  # getlocal0 pushscope getlocal0 constructsuper 0 returnvoid
    cinit = [0xD0, 0x30, 0x47]
    script = bytearray([0xD0, 0x30, 0x65, 0x00])  # getlocal0 pushscope getscopeobject 0
    for name in base_names:
        script += bytes([0x60]) + u30(name) + bytes([0x30])  # getlex base; pushscope
    script += bytes([0x60]) + u30(movieclip)  # getlex MovieClip (base for newclass)
    script += bytes([0x58]) + u30(0)  # newclass 0
    script += bytes([0x1D] * len(base_names))  # popscope
    script += bytes([0x68]) + u30(own) + bytes([0x47])  # initproperty; returnvoid

    abc += u30(3)
    abc += body(0, 1, 1, iinit)
    abc += body(1, 1, 1, cinit)
    abc += body(2, 2, len(base_names) + 1, script)
    return bytes(abc)


def tag(code, payload):
    if len(payload) < 0x3F:
        return struct.pack("<H", (code << 6) | len(payload)) + payload
    return struct.pack("<HI", (code << 6) | 0x3F, len(payload)) + payload


def rect(xmax, ymax):
    nbits = max(v.bit_length() for v in (xmax, ymax)) + 1
    bits = format(nbits, "05b") + "".join(format(v, f"0{nbits}b") for v in (0, xmax, 0, ymax))
    bits += "0" * (-len(bits) % 8)
    return bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))


def swf(class_name):
    body = rect(STAGE_W * 20, STAGE_H * 20) + struct.pack("<HH", FRAME_RATE << 8, 1)
    body += tag(69, struct.pack("<I", 0x08))  # FileAttributes: ActionScript 3
    body += tag(9, b"\x00\x00\x00")  # SetBackgroundColor
    body += tag(82, struct.pack("<I", 1) + b"\x00" + abc_for(class_name))  # DoABC2, lazy
    body += tag(76, struct.pack("<HH", 1, 0) + class_name.encode() + b"\x00")  # SymbolClass
    body += tag(1, b"") + tag(0, b"")  # ShowFrame, End
    return b"FWS" + bytes([SWF_VERSION]) + struct.pack("<I", 8 + len(body)) + body


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    with open(sys.argv[1], "wb") as f:
        f.write(swf(sys.argv[2]))
