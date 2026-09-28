import { randomBytes, randomUUID } from "node:crypto";

export function pad(n: number): string {
	return String(n).padStart(2, "0");
}

export function stamp(d = new Date()): string {
	return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

export function month(d = new Date()): string {
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
}

export function pid(): string {
	try {
		return randomBytes(2).toString("hex");
	} catch {
		return randomUUID().replace(/-/g, "").slice(0, 4);
	}
}

export function markdownDateTime(d = new Date()): {
	date: string;
	time: string;
} {
	return {
		date: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
		time: `${pad(d.getHours())}:${pad(d.getMinutes())}`,
	};
}
