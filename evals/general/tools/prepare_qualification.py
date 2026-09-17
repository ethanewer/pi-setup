#!/usr/bin/env python3
"""Assemble and enqueue the balanced 24-candidate qualification inventory."""
import argparse
import hashlib
import json
from pathlib import Path

from generate_tasks import Queue


SKILLS = [
 ('cobalt-lantern','typer-cli-contract-testing','https://github.com/fastapi/typer','a80f6e5ecd74f32b983cca336a2f3cba98d9853a','MIT','python','cli tooling','typed cli contract repair'),
 ('maple-circuit','starlette-asgi-lifecycle-debugging','https://github.com/encode/starlette','03f12b7fcf0a3e21a8da648ca0900c79472e9efe','BSD-3-Clause','python','web frameworks','asgi lifecycle diagnosis'),
 ('ivory-keel','just-recipe-interface-auditing','https://github.com/casey/just','5969e396f4e5c98b64a5df929e3ee67629295d6e','CC0-1.0','rust','build automation','recipe interface audit'),
 ('quartz-orbit','d3-data-join-validation','https://github.com/d3/d3','ca958d45217b4c15332d971b935451a6d4c978f4','ISC','javascript','data visualization','keyed data join validation'),
 ('velvet-signal','duckdb-query-plan-diagnosis','https://github.com/duckdb/duckdb','cdb0429ca6f4d8c01cf7d1a0b144cf3b95f01b46','MIT','cpp sql','databases','bounded query plan diagnosis'),
 ('cedar-prism','gin-middleware-contract-testing','https://github.com/gin-gonic/gin','dcaa4296d111981ffb31ac3eba90bb63e1eb5ab9','MIT','go','web frameworks','middleware contract validation'),
 ('lunar-canvas','eslint-flat-config-debugging','https://github.com/eslint/eslint','22b09f54f67a9512d4cea39ddbab9b6973d5c476','MIT','javascript','static analysis','flat config diagnosis'),
 ('silver-rivet','gradle-dependency-resolution-diagnosis','https://github.com/gradle/gradle','45f98545be7d8c57a6070969df5eb80bea3b0834','Apache-2.0','java kotlin','build systems','dependency resolution diagnosis'),
]
REPO_NAMES = ['amber-harbor','birch-vector','copper-meadow','delta-cairn',
              'ember-brook','fennel-bridge','granite-sparrow','hazel-cipher']
PR_NAMES = ['indigo-anchor','juniper-falcon','kelp-mosaic','linen-grove',
            'marble-tide','nickel-wren','ochre-vault','pebble-flux']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', type=Path, required=True)
    parser.add_argument('--campaign-root', type=Path, required=True)
    parser.add_argument('--repo-plan', type=Path, required=True)
    parser.add_argument('--pr-plan', type=Path, required=True)
    parser.add_argument('--source-inventory', type=Path, required=True)
    args = parser.parse_args()
    root = args.campaign_root.resolve()
    identity_dir = root / 'identities'
    identity_dir.mkdir(exist_ok=False)
    queue = Queue(args.db)
    source_records = json.loads(args.source_inventory.read_text())['sources']
    licenses = {item['repository']: item['license'] for item in source_records}
    skill_root = root / 'skill-generation/batch-004/workspace/skills'
    records = []
    for task_id, skill_name, repository, revision, license_name, language, domain, family in SKILLS:
        artifact = skill_root / skill_name / 'SKILL.md'
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        identity = {'lane':'skills','repository':repository,'revision':revision,
          'reference':'','skill_hash':digest,'skill_artifact':str(artifact.resolve()),
          'license':license_name,
          'family':family,'language':language,'domain':domain,
          'workflow':{
            'outcome':f'apply {skill_name} to diagnose and repair an original offline scenario',
            'decisions':['select the minimal behavioral contract and preserve unrelated behavior'],
            'deliverables':['working implementation and executable regression checks'],
            'failure_modes':['visible example is hard coded','edge behavior violates the contract','diagnostics hide the root cause'],
            'distinguishers':[f'new scenario grounded by {skill_name} without copying upstream tests'],
            'test_structure':['visible reproduction plus hidden behavioral and adversarial cases'],
            'skill_coverage':[skill_name,'regression diagnosis','behavioral verification']}}
        records.append((task_id, identity))
    for names, plan_path in ((REPO_NAMES,args.repo_plan),(PR_NAMES,args.pr_plan)):
        identities = json.loads(plan_path.read_text())['identities']
        if len(identities) != 8:
            raise ValueError(f'{plan_path} does not contain 8 identities')
        for identity in identities:
            identity['license'] = licenses[identity['repository']]
        records.extend(zip(names, identities))
    manifest=[]
    for task_id, identity in records:
        path=identity_dir/(task_id+'.json')
        path.write_text(json.dumps(identity,indent=2)+'\n')
        queued=queue.enqueue(identity['lane'],identity['repository'],3,identity=identity,task_id=task_id)
        manifest.append({'task_id':queued,'lane':identity['lane'],'identity':str(path)})
        source_dir=root/'sources'; source_dir.mkdir(exist_ok=True)
        (source_dir/(task_id+'.json')).write_text(json.dumps({'identity':identity},indent=2)+'\n')
    (root/'qualification-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'enqueued':len(manifest),'by_lane':{lane:sum(x['lane']==lane for x in manifest)
          for lane in ('skills','repo','pr-issue')}},indent=2))


if __name__=='__main__':
    main()
