"""Install your own Xbox 360 content packages (DLC, saves) into the PC port.

Extracts STFS packages (CON / LIVE / PIRS) into the layout the ReXGlue runtime
reads, mirroring rex::system::xam::ContentManager::InstallContent and
WriteContentHeaderFile:

  <root>/<XUID>/<TITLE>/<TYPE>/<package name>/<files...>
  <root>/<XUID>/<TITLE>/Headers/<TYPE>/<package name>.header

The header is XCONTENT_AGGREGATE_DATA (0x148 bytes); DLC headers get a trailing
big-endian u32 license mask. DLC (type 00000002) goes under the shared XUID
0000000000000000; saves (type 00000001) go under the local profile XUID.

No game content is included with this tool. Use packages copied from your own
console / your own purchases.

usage:
  py tools\\install_xcontent.py [--list] [--root DIR] [--profile-xuid HEX] PATH...

PATH may be a package file or a folder (searched recursively for packages).
--list only prints the package contents and writes nothing.
--root defaults to %USERPROFILE%\\Documents\\FIFA World Cup 2010.
"""
import os, struct, sys

BLK = 0x1000
L0, L1 = 170, 170 * 170
END = 0xFFFFFF


def u24le(b, o):
    return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16)


class Stfs:
    def __init__(self, path):
        self.f = open(path, 'rb')
        h = self.f.read(0x971A)
        self.h = h
        self.magic = h[:4]
        if self.magic not in (b'CON ', b'LIVE', b'PIRS'):
            raise ValueError('not an STFS package')
        self.header_size = struct.unpack('>I', h[0x340:0x344])[0]
        self.content_type = struct.unpack('>I', h[0x344:0x348])[0]
        self.title_id = struct.unpack('>I', h[0x360:0x364])[0]
        self.volume_type = struct.unpack('>I', h[0x3A9:0x3AD])[0]
        if self.volume_type != 0:
            raise ValueError('SVOD packages not supported')
        flags = h[0x37B]
        self.read_only = flags & 1
        self.root_active = (flags >> 1) & 1
        self.ft_count = struct.unpack('<H', h[0x37C:0x37E])[0]
        self.ft_block = u24le(h, 0x37E)
        self.total_blocks = struct.unpack('>I', h[0x395:0x399])[0]
        self.display_name = h[0x411:0x411 + 0x100].decode('utf-16-be', 'replace').split('\x00')[0]
        self.bpht = 1 if self.read_only else 2
        self.step0 = L0 + self.bpht
        self.step1 = L1 + (L0 + 1) * self.bpht
        self.base = (self.header_size + BLK - 1) & ~(BLK - 1)
        self.cache = {}

    def block_off(self, idx):
        base, block = L0, idx
        for _ in range(3):
            block += ((idx + base) // base) * self.bpht
            if idx < base:
                break
            base *= L0
        return self.base + (block << 12)

    def hash_block_num(self, idx, level):
        if level == 0:
            if idx < L0:
                return 0
            b = (idx // L0) * self.step0 + ((idx // L1) + 1) * self.bpht
            return b if idx < L1 else b + self.bpht
        if level == 1:
            if idx < L1:
                return self.step0
            return (idx // L1) * self.step1 + self.bpht
        return self.step1

    def table(self, off):
        if off not in self.cache:
            self.f.seek(off)
            self.cache[off] = self.f.read(BLK)
        return self.cache[off]

    def entry_info(self, tbl, rec):
        return struct.unpack('>I', tbl[rec * 0x18 + 0x14:rec * 0x18 + 0x18])[0]

    def next_block(self, idx):
        sec = BLK if self.root_active else 0
        off0 = self.base + (self.hash_block_num(idx, 0) << 12)
        if self.read_only:
            sec = 0
        elif self.total_blocks > L0:
            off1 = self.base + (self.hash_block_num(idx, 1) << 12)
            if self.total_blocks > L1:
                off2 = self.base + (self.hash_block_num(idx, 2) << 12)
                info = self.entry_info(self.table(off2 + sec), (idx // L1) % L0)
                sec = BLK if info & 0x40000000 else 0
            info = self.entry_info(self.table(off1 + sec), (idx // L0) % L0)
            sec = BLK if info & 0x40000000 else 0
        info = self.entry_info(self.table(off0 + sec), idx % L0)
        return info & 0xFFFFFF

    def entries(self):
        out, blk = [], self.ft_block
        for _ in range(self.ft_count):
            self.f.seek(self.block_off(blk))
            d = self.f.read(BLK)
            for m in range(BLK // 0x40):
                e = d[m * 0x40:(m + 1) * 0x40]
                if e[0] == 0:
                    break
                fl = e[0x28]
                out.append(dict(
                    name=e[:fl & 0x3F].decode('latin-1'),
                    is_dir=bool(fl & 0x80),
                    alloc=u24le(e, 0x2C),
                    start=u24le(e, 0x2F),
                    parent=struct.unpack('>H', e[0x32:0x34])[0],
                    length=struct.unpack('>I', e[0x34:0x38])[0]))
            blk = self.next_block(blk)
            if blk == END:
                break
        return out

    def path_of(self, ents, i):
        parts = []
        while i != 0xFFFF:
            parts.append(ents[i]['name'])
            i = ents[i]['parent']
        return '/'.join(reversed(parts))

    def read_file(self, e):
        data, idx, rem, blocks = bytearray(), e['start'], e['length'], 0
        while rem and idx != END:
            self.f.seek(self.block_off(idx))
            n = min(BLK, rem)
            data += self.f.read(n)
            rem -= n
            blocks += 1
            idx = self.next_block(idx)
        if rem or blocks != e['alloc']:
            raise IOError(f"bad block chain for {e['name']}: {rem} bytes missing, "
                          f"{blocks}/{e['alloc']} blocks")
        return bytes(data)


def aggregate(content_type, display_name, file_name, xuid, title_id):
    b = bytearray(0x148)
    struct.pack_into('>II', b, 0, 1, content_type)  # device_id = HDD
    dn = display_name.encode('utf-16-be')[:0xFE]
    b[8:8 + len(dn)] = dn
    fn = file_name.encode('latin-1')[:42]  # char[42], may be unterminated
    b[0x108:0x108 + len(fn)] = fn
    struct.pack_into('>Q', b, 0x138, xuid)
    struct.pack_into('>I', b, 0x140, title_id)
    return bytes(b)


DEFAULT_ROOT = os.path.join(os.path.expanduser('~'), 'Documents', 'FIFA World Cup 2010')
DEFAULT_PROFILE_XUID = 0xB13EBABEBABEBABE  # the runtime's default local profile


def find_packages(paths):
    for p in paths:
        if os.path.isdir(p):
            for d, _, names in os.walk(p):
                for n in sorted(names):
                    yield from find_packages([os.path.join(d, n)])
        elif os.path.isfile(p):
            with open(p, 'rb') as fh:
                if fh.read(4) in (b'CON ', b'LIVE', b'PIRS'):
                    yield p
        else:
            print(f'not found: {p}', file=sys.stderr)


def main(argv):
    root, profile, paths, list_only = DEFAULT_ROOT, DEFAULT_PROFILE_XUID, [], False
    it = iter(argv)
    for a in it:
        if a == '--root':
            root = next(it)
        elif a == '--profile-xuid':
            profile = int(next(it), 16)
        elif a == '--list':
            list_only = True
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        else:
            paths.append(a)
    if not paths:
        print(__doc__)
        return 1
    if list_only:
        root = None
    found = 0
    for p in find_packages(paths):
        found += 1
        s = Stfs(p)
        pkg_name = os.path.basename(p)
        ents = s.entries()
        title = s.title_id or 0x454108E4
        print(f'== {pkg_name}  [{s.magic.decode().strip()} type={s.content_type:08X} '
              f'title={title:08X} ro={s.read_only} blocks={s.total_blocks}] "{s.display_name}"')
        files = []
        for i, e in enumerate(ents):
            rel = s.path_of(ents, i)
            if e['is_dir']:
                print(f'   [dir] {rel}/')
                continue
            data = s.read_file(e)
            files.append((rel, data))
            print(f'   {len(data):>10}  {rel}')
        if root is None:
            continue
        if s.content_type == 2:
            xuid, license_tail = 0, struct.pack('>I', 0xFFFFFFFF)
        else:
            xuid, license_tail = profile, b''
        xuid_s, title_s, type_s = f'{xuid:016X}', f'{title:08X}', f'{s.content_type:08X}'
        dest = os.path.join(root, xuid_s, title_s, type_s, pkg_name)
        hdr = os.path.join(root, xuid_s, title_s, 'Headers', type_s, pkg_name + '.header')
        for rel, data in files:
            out = os.path.join(dest, *rel.split('/'))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, 'wb') as fh:
                fh.write(data)
        os.makedirs(os.path.dirname(hdr), exist_ok=True)
        name = s.display_name or pkg_name
        with open(hdr, 'wb') as fh:
            fh.write(aggregate(s.content_type, name, pkg_name, xuid, title) + license_tail)
        print(f'   -> {dest}\n   -> {hdr}')
    if not found:
        print('no STFS packages found', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
