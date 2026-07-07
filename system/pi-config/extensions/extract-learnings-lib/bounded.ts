export async function runBounded(
	ms: number,
	fn: (signal: AbortSignal) => Promise<void>,
): Promise<void> {
	const controller = new AbortController();
	let timer: ReturnType<typeof setTimeout> | undefined;
	const guard = new Promise<void>((resolve) => {
		timer = setTimeout(() => {
			controller.abort();
			resolve();
		}, ms);
	});
	try {
		await Promise.race([fn(controller.signal).catch(() => {}), guard]);
	} finally {
		if (timer) clearTimeout(timer);
	}
}
