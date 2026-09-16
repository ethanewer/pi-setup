type Factory = {
  readonly version: number;
  'new'(kind: string): Factory;
  'build'(): Factory;
};