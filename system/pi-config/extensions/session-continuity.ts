import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	archiveCurrentJournal,
	selectSessionArchiveTarget,
	writeFreshJournal,
} from "./session-continuity-lib/journal";
import { isIncognito } from "./brain-paths";

export { selectSessionArchiveTarget };

export default function sessionContinuity(pi: ExtensionAPI): void {
	pi.on("session_start", async (_event, ctx) => {
		// Read-only session: don't archive or rewrite the journal (both are writes).
		if (isIncognito()) {
			ctx.ui.setStatus("agentBrain-session", "session: incognito (read-only)");
			return;
		}
		try {
			const previous = await archiveCurrentJournal();
			await writeFreshJournal(previous);
			ctx.ui.setStatus("agentBrain-session", sessionStatus(previous));
		} catch (err) {
			ctx.ui.setStatus("agentBrain-session", "session: journal error");
			ctx.ui.notify(
				`agentBrain session continuity failed: ${errorText(err)}`,
				"warning",
			);
		}
	});
}

function sessionStatus(previous: string | undefined): string {
	return previous ? `session: archived ${previous}` : "session: journal ready";
}

function errorText(err: unknown): string {
	return err instanceof Error ? err.message : String(err);
}
