/**
 * TPS Tracker Extension
 *
 * Tracks tokens per second during model generation and reports
 * final TPS statistics at the end of each agent run.
 */

import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";

type TrackerState = {
	messageStart: number | null;
	streamStart: number | null;
	estimatedStreamedTokens: number;
	totalOutputTokens: number;
	totalStreamMs: number;
};

function createState(): TrackerState {
	return {
		messageStart: null,
		streamStart: null,
		estimatedStreamedTokens: 0,
		totalOutputTokens: 0,
		totalStreamMs: 0,
	};
}

function resetRun(state: TrackerState): void {
	state.totalOutputTokens = 0;
	state.totalStreamMs = 0;
	resetMessage(state);
}

function resetMessage(state: TrackerState): void {
	state.messageStart = null;
	state.streamStart = null;
	state.estimatedStreamedTokens = 0;
}

function outputDelta(streamEvent: unknown): string | undefined {
	if (!streamEvent || typeof streamEvent !== "object") return undefined;
	const event = streamEvent as { type?: string; delta?: string };
	if (
		!["text_delta", "thinking_delta", "toolcall_delta"].includes(
			event.type ?? "",
		)
	) {
		return undefined;
	}
	return event.delta ?? "";
}

function tokenLabel(officialTokens: number, estimatedTokens: number): string {
	return officialTokens > 0
		? `${officialTokens} tok`
		: `~${Math.round(estimatedTokens)} tok`;
}

function liveStatus(
	theme: Theme,
	tps: number,
	tokens: string,
	elapsed: number,
): string {
	return `${theme.fg("accent", `${tps} tok/s`)} ${theme.fg("dim", `(${tokens} / ${elapsed.toFixed(1)}s)`)}`;
}

function finalStatus(
	theme: Theme,
	totalTokens: number,
	elapsed: number,
): {
	notification: string;
	status: string;
} {
	const tps =
		totalTokens > 0 && elapsed > 0 ? Math.round(totalTokens / elapsed) : 0;
	const icon = theme.fg("success", "✓");
	const tpsLabel =
		tps > 0 ? theme.fg("accent", `${tps} tok/s`) : theme.fg("dim", "N/A");
	const detail = theme.fg(
		"dim",
		`${totalTokens} tokens in ${elapsed.toFixed(1)}s streaming`,
	);
	return {
		notification: `${icon} ${tpsLabel}  ${detail}`,
		status: theme.fg("dim", `done — ${tpsLabel}`),
	};
}

export default function tpsTrackerExtension(pi: ExtensionAPI): void {
	const state = createState();

	pi.on("agent_start", (_event, ctx) => {
		resetRun(state);
		ctx.ui.setStatus("tps", ctx.ui.theme.fg("dim", "⏱ generating..."));
	});

	pi.on("message_start", (event) => {
		if (event.message.role !== "assistant") return;
		state.messageStart = Date.now();
		state.streamStart = null;
		state.estimatedStreamedTokens = 0;
	});

	pi.on("message_update", (event, ctx) => {
		if (event.message.role !== "assistant") return;
		const delta = outputDelta(event.assistantMessageEvent);
		if (delta === undefined) return;

		const now = Date.now();
		state.streamStart ??= now;
		state.estimatedStreamedTokens += Math.max(0, delta.length / 4);

		const elapsed = (now - state.streamStart) / 1000;
		const officialTokens = event.message.usage.output;
		const currentTokens =
			officialTokens > 0 ? officialTokens : state.estimatedStreamedTokens;
		if (elapsed <= 0 || currentTokens <= 0) return;

		ctx.ui.setStatus(
			"tps",
			liveStatus(
				ctx.ui.theme,
				Math.round(currentTokens / elapsed),
				tokenLabel(officialTokens, state.estimatedStreamedTokens),
				elapsed,
			),
		);
	});

	pi.on("message_end", (event) => {
		if (event.message.role !== "assistant") return;
		const messageTokens = event.message.usage.output;
		const timingStart = state.streamStart ?? state.messageStart;
		if (!timingStart || messageTokens <= 0) {
			resetMessage(state);
			return;
		}
		state.totalOutputTokens += messageTokens;
		state.totalStreamMs += Math.max(0, Date.now() - timingStart);
		resetMessage(state);
	});

	pi.on("agent_end", (_event, ctx) => {
		const elapsed = state.totalStreamMs / 1000;
		const summary = finalStatus(ctx.ui.theme, state.totalOutputTokens, elapsed);
		ctx.ui.notify(summary.notification, "info");
		ctx.ui.setStatus("tps", summary.status);
	});
}
