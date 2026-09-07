# -*- coding: utf-8 -*-
"""Generate Plugins/Roster/EnchantData.lua from the CLA workbook.

Mechanical transcription - no hand entry - so the 136-row table cannot pick up
typos. Re-run this if the source workbook is ever updated:

    python Tools/gen_enchant_data.py ["path/to/workbook.xlsx"]

The workbook is the owner's own CLA copy and is not checked in, so the path is
resolved from argv[1] first and only then from the usual Downloads location.
"""
import zipfile, re, collections, io, os, sys

NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'

_DEFAULT = os.path.expanduser(os.path.join(
    '~', 'Downloads',
    'Copie de WoW Classic TBC - Combat Log Analytics V1.6.0a.xlsx'))

XLSX = sys.argv[1] if len(sys.argv) > 1 else _DEFAULT
if not os.path.exists(XLSX):
    sys.exit('workbook not found: %s\nPass its path as the first argument.' % XLSX)

DEST = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    '..', 'Plugins', 'Roster', 'EnchantData.lua'))

from xml.etree import ElementTree as ET

z = zipfile.ZipFile(XLSX)
ss = []
for si in ET.fromstring(z.read('xl/sharedStrings.xml')):
    ss.append(''.join(t.text or '' for t in si.iter(NS + 't')))

cells = {}
for c in ET.fromstring(z.read('xl/worksheets/sheet2.xml')).iter(NS + 'c'):
    ref, t, v = c.get('r'), c.get('t'), c.find(NS + 'v')
    if v is None:
        continue
    val = ss[int(v.text)] if t == 's' else v.text
    m = re.match(r'([A-Z]+)(\d+)', ref)
    cells.setdefault(int(m.group(2)), {})[m.group(1)] = val

# WCL 0-based slot index -> AltTracker slot key
SLOT = {0: 'head', 2: 'shoulder', 4: 'chest', 6: 'legs', 7: 'feet',
        8: 'wrist', 9: 'hands', 14: 'back', 15: 'mainhand', 16: 'offhand'}

bad = {}
nrows = 0
for k in sorted(cells):
    if k < 5:
        continue
    b = cells[k].get('B')
    if not b:
        continue
    nrows += 1
    name = (cells[k].get('C') or '').strip()
    m = re.match(r'^\s*(\d+)\s*(?:\[(\d+)\])?\s*$', b)
    assert m, 'unparsed enchant cell %r' % b
    eid = int(m.group(1))
    slot = int(m.group(2)) if m.group(2) else None
    e = bad.setdefault(eid, {'any': None, 'slots': collections.OrderedDict()})
    if slot is None:
        assert e['any'] in (None, name), 'conflicting bare name for %d' % eid
        e['any'] = name
    else:
        assert slot in SLOT, 'unmapped slot index %d (enchant %d)' % (slot, eid)
        key = SLOT[slot]
        assert e['slots'].get(key) in (None, name), 'conflicting name %d/%s' % (eid, key)
        e['slots'][key] = name

excl = []
for k in sorted(cells):
    if k < 5:
        continue
    e = cells[k].get('E')
    if not e:
        continue
    excl.append((int(float(e)), (cells[k].get('F') or '').strip()))

# Meta gem activation, ported from the metaGemActive block of the CLA script.
# CLA uses strict ">" on counts; these minimums are the equivalent ">=".
METAS = [
    (25890, 'red = 2, blue = 2, yellow = 2'),
    (25893, 'moreBlueThanYellow = true'),
    (25894, 'red = 1, yellow = 2'),
    (25895, 'moreRedThanYellow = true'),
    (25896, 'blue = 3'),
    (25897, 'moreRedThanBlue = true'),
    (25898, 'blue = 5'),
    (25899, 'red = 2, blue = 2, yellow = 2'),
    (25901, 'red = 2, blue = 2, yellow = 2'),
    (28556, 'red = 1, yellow = 2'),
    (28557, 'red = 1, yellow = 2'),
    (32409, 'red = 2, blue = 2, yellow = 2'),
    (32410, 'red = 2, blue = 2, yellow = 2'),
    (32640, 'moreBlueThanYellow = true'),
    (32641, 'yellow = 3'),
    (34220, 'blue = 2'),
    (35501, 'blue = 2, yellow = 1'),
    (35503, 'red = 3'),
]


def q(s):
    return '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')


H = '''------------------------------------------------------------
-- AltTracker Roster - Enchant / gem audit reference data (TBC)
--
-- Provenance: transcribed mechanically (never by hand) from the "gear issues"
--   sheet of "WoW Classic TBC - Combat Log Analytics V1.6.0a.xlsx" (CLA).
--   Columns B/C are its "cheap or bad enchants" table; columns E/F its
--   "excluded gear" list. Regenerate with Tools/gen_enchant_data.py rather
--   than editing this file by hand.
--
-- IMPORTANT - DATA QUALITY
--   DO NOT add entries from memory or rough estimation. Every row below came
--   out of the workbook verbatim. To extend the table, extend the source
--   workbook and re-transcribe. When in doubt, omit the entry.
--
-- Schema:
--   AltTracker.BadEnchants[enchantID] = {
--       any   = "name",              -- applies to any slot (may be nil)
--       slots = { feet = "name" },   -- slot-restricted names (may be absent)
--   }
--   Lookup order is slots[slotKey] first, then any. Two enchant IDs carry BOTH
--   forms (255 and 723), and one ID can be restricted to several slots with a
--   different label each (2841 covers five), so a flat [id] = name map would
--   silently lose rows.
--
-- CLA judges enchants by denylist: a slot with no enchant is "missing", an
-- enchant listed here is "subpar", and anything else is treated as fine. That
-- means unavoidable false negatives for any weak enchant the workbook omits -
-- present these as CLA-derived advice, not authoritative truth.
--
-- TBC item data is static, so this set is closed and needs no refresh.
------------------------------------------------------------

AltTracker = AltTracker or {}

'''

L = [H.rstrip('\n'), '']
L.append('-- %d workbook rows -> %d distinct enchant IDs' % (nrows, len(bad)))
L.append('AltTracker.BadEnchants = {')
for eid in sorted(bad):
    e = bad[eid]
    parts = []
    if e['any'] is not None:
        parts.append('any = %s' % q(e['any']))
    if e['slots']:
        parts.append('slots = { %s }' % ', '.join(
            '%s = %s' % (k, q(v)) for k, v in e['slots'].items()))
    L.append('    [%d] = { %s },' % (eid, ', '.join(parts)))
L.append('}')
L.append('')
L.append('-- Slots that can carry a permanent enchant in TBC.')
L.append('--')
L.append('-- Rings are Enchanting-only, so CLA skips them and so do we: profession')
L.append('-- eligibility is not derivable from a synced record. Ranged is deferred -')
L.append('-- scopes apply only to bows/guns/crossbows, never to wands, thrown, idols,')
L.append('-- librams or totems, so it needs its own subtype gate.')
L.append('--')
L.append('-- offhand is CONDITIONAL, resolved in Audit.lua: an offhand WEAPON takes')
L.append('-- weapon enchants and a SHIELD takes shield enchants; only a held-in-')
L.append('-- off-hand frill (INVTYPE_HOLDABLE) cannot be enchanted at all.')
L.append('AltTracker.ENCHANTABLE_SLOTS = {')
L.append('    head = true, shoulder = true, chest = true, legs = true, feet = true,')
L.append('    wrist = true, hands = true, back = true, mainhand = true, offhand = true,')
L.append('}')
L.append('')
L.append('-- Items CLA never flags (fishing poles, joke/utility gear, ...).')
L.append('AltTracker.AuditExcludedItems = {')
for iid, name in excl:
    L.append('    [%d] = true,  -- %s' % (iid, name))
L.append('}')
L.append('')
L.append('------------------------------------------------------------')
L.append('-- Meta gem activation requirements')
L.append('--')
L.append('-- Ported from the metaGemActive block of the CLA script. Requirements come')
L.append('-- in TWO shapes, and a single minimum-count rule would misclassify several:')
L.append('--   * minimum counts  - red / blue / yellow  (">=" thresholds)')
L.append('--   * relative counts - moreRedThanBlue, moreRedThanYellow,')
L.append('--                       moreBlueThanYellow')
L.append('-- CLA writes these as strict ">" comparisons; the minimums below are the')
L.append('-- equivalent ">=" values.')
L.append('------------------------------------------------------------')
L.append('')
L.append('AltTracker.MetaGems = {')
for gid, req in METAS:
    L.append('    [%d] = { %s },' % (gid, req))
L.append('}')
L.append('')

io.open(DEST, 'w', encoding='utf-8', newline='\n').write('\n'.join(L))
print('rows=%d ids=%d excluded=%d metas=%d' % (nrows, len(bad), len(excl), len(METAS)))
