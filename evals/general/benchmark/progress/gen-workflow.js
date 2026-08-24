export const meta = {
  name: 'bench-gen',
  description: 'Generate harbor benchmark tasks from skills.json in buckets',
  phases: [{ title: 'generate' }],
};

const BENCH = '/Users/ethanewer/pi-setup/evals/general/benchmark';

phase('generate');

const buckets = args.buckets; // [{id, kind, tasks:[...]}]
const guide = await agent(
  `Read the file ${BENCH}/progress/TASK_AUTHOR_GUIDE.md and reply with the single word READY.`,
  { label: 'warmup' }
);
log('guide warmup: ' + guide);

const results = await parallel(
  buckets.map((bucket) => () =>
    agent(
      [
        `You are authoring Harbor benchmark tasks. First read ${BENCH}/progress/TASK_AUTHOR_GUIDE.md in full and follow it exactly.`,
        `The benchmark root is ${BENCH}. All task directories go under ${BENCH}/tasks/.`,
        '',
        `Your bucket: ${bucket.id} (kind=${bucket.kind}). Author EVERY task listed below:`,
        '',
        '```json',
        JSON.stringify(bucket.tasks, null, 1),
        '```',
        '',
        'For each task object:',
        '- name: the exact directory name under tasks/.',
        '- kind=main/hard: the task must exercise ALL listed soft_skills and technical_skills of the item in one coherent scenario (hard tasks: deeper, multi-stage, adversarial; medium tasks: solid multi-step). Tag task.toml with item id + skill slugs.',
        '- kind=skill-probe: an easy/trivial task that requires the agent to demonstrate or know exactly that one technical skill. Keep it minimal and fast (reward check should take seconds).',
        '',
        'Workflow for EACH task:',
        '1. Optionally browse reference corpora under ' + BENCH + '/reference/corpus/ (see MANIFEST.json) for a matching task to adapt; otherwise create from scratch.',
        '2. Create tasks/<name>/ with task.toml, instruction.md, environment/Dockerfile (+environment/files/ if needed), solution/solve.sh, tests/test.sh (+ helper test files if needed).',
        '3. Validate the Dockerfile statically: FROM must be bench-base:ubuntu-24.04, bench-base:python-3.12, bench-base:node-22, or an official image with the CA-patch layer (copy ' + BENCH + '/certs/corp-root-ca.pem into environment/ when using a non-bench-base FROM).',
        '4. Lint: task.toml parses as TOML, instruction.md non-empty and self-contained, tests/test.sh writes /logs/verifier/reward.txt on every path, solve.sh would produce reward=1.',
        '5. Do NOT docker build or run anything; static validation only.',
        '',
        'When you finish ALL tasks in your bucket, append one line per task to ' + BENCH + '/progress/' + bucket.id + '.done with format: <task-name>\t<short status note>. Then reply with a JSON array of the task names you completed.',
      ].join('\n'),
      { label: bucket.id }
    )
  )
);

const done = [];
const failed = [];
results.forEach((r, i) => {
  if (r === null) failed.push(buckets[i].id);
  else done.push({ bucket: buckets[i].id, result: typeof r === 'string' ? r.slice(0, 500) : r });
});

return { completedBuckets: done.length, failedBuckets: failed, done };
