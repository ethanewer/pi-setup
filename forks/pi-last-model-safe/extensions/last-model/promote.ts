export function promoteModel(patterns: string[] | undefined, modelReference: string): string[] | undefined {
	if (!patterns?.length) return patterns;
	const normalized = modelReference.toLowerCase();
	return [modelReference, ...patterns.filter((pattern) => pattern.toLowerCase() !== normalized)];
}
