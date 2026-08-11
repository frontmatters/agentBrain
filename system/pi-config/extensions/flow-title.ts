import path from "node:path";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";

const DEEP_BLUE: Rgb = [22, 83, 189];
const BLUE: Rgb = [48, 129, 247];
const SKY: Rgb = [93, 171, 255];
const ICE: Rgb = [151, 205, 255];
const PALETTE: Rgb[] = [DEEP_BLUE, BLUE, SKY, ICE, SKY, BLUE];

type Rgb = [number, number, number];
const TITLE_LINES = [
	"  ██████╗  ██╗ ",
	"  ██╔══██╗ ██║ ",
	"  ██████╔╝ ██║ ",
	"  ██╔═══╝  ██║ ",
	"  ██║      ██║ ",
	"  ╚═╝      ╚═╝ ",
];

function mix(a: number, b: number, t: number) {
	return Math.round(a + (b - a) * t);
}

function sampleGradient(position: number) {
	const wrapped = ((position % 1) + 1) % 1;
	const scaled = wrapped * PALETTE.length;
	const index = Math.floor(scaled);
	const nextIndex = (index + 1) % PALETTE.length;
	const t = scaled - index;
	const a = PALETTE[index] ?? DEEP_BLUE;
	const b = PALETTE[nextIndex] ?? DEEP_BLUE;
	return [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)] as Rgb;
}

function fg([r, g, b]: Rgb, text: string) {
	return `\x1b[38;2;${r};${g};${b}m${text}${RESET}`;
}

function gradientText(text: string, phase: number) {
	const chars = [...text];
	const span = Math.max(chars.length - 1, 1);
	return chars
		.map((char, index) => {
			if (char === " ") return char;
			return fg(sampleGradient(index / span + phase), char);
		})
		.join("");
}

function center(text: string, width: number) {
	const length = [...text].length;
	if (length >= width) return text;
	return `${" ".repeat(Math.floor((width - length) / 2))}${text}`;
}

function projectName() {
	return path.basename(process.cwd()) || "session";
}

function renderHeader(width: number, phase: number, subtitleText: string) {
	const lines = TITLE_LINES.map((line, row) =>
		gradientText(center(line, width), phase + row * 0.045),
	);
	const subtitle = center(subtitleText, width);

	return [
		"",
		...lines,
		`${BOLD}${gradientText(subtitle, phase + 0.18)}${RESET}`,
		"",
	];
}

export default function (pi: ExtensionAPI) {
	let requestRender: (() => void) | undefined;
	let currentModelId = "no model selected";

	function installHeader(ctx: ExtensionContext) {
		ctx.ui.setHeader((tui) => {
			requestRender = () => tui.requestRender();
			return {
				render(width: number) {
					return renderHeader(width, 0, `${currentModelId} · ${projectName()}`);
				},
				invalidate() {
					tui.requestRender();
				},
			};
		});
	}

	pi.on("session_start", (_event, ctx) => {
		currentModelId = ctx.model?.id ?? "no model selected";
		if (!ctx.hasUI) return;
		installHeader(ctx);
	});

	pi.on("model_select", (event) => {
		currentModelId = event.model.id;
		requestRender?.();
	});

	pi.on("session_shutdown", (_event, ctx) => {
		if (ctx.hasUI) ctx.ui.setHeader(undefined);
	});

	pi.registerCommand("flow-title", {
		description: "Enable the blue flowing gradient session header",
		handler: (_args, ctx) => {
			installHeader(ctx);
			ctx.ui.notify("Flow title enabled", "info");
			return Promise.resolve();
		},
	});

	pi.registerCommand("flow-title-builtin", {
		description: "Restore pi's built-in header for this session",
		handler: (_args, ctx) => {
			ctx.ui.setHeader(undefined);
			ctx.ui.notify("Built-in header restored", "info");
			return Promise.resolve();
		},
	});
}
