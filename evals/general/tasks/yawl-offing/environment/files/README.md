# yawl-offing

No fixtures are shipped: the agent authors its own failing reproduction
(`/app/repro.py`) and change summary (`/app/summary.md`) as deliverables. The
upstream tree is cloned and installed at image build time by
`environment/Dockerfile`; the golden regression test is extracted from the
upstream fix commit into `/opt/golden/` at build time and planted by the
verifier.