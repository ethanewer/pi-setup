interface Registry<K, V> {
  count: number;
  "new"(key: K, value: V): Registry<K, V>;
  get(key: K): V;
}