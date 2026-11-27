import type { Plugin } from "vite";

export function coreVersion(bytes: Uint8Array | undefined): string;
export function shellFiles(bundleFiles: string[], version: string): string[];
export function workerSource(template: string, files: string[], options: { contents: (string | Uint8Array)[]; media: string }): string;
export function mediaFiles(publicDir: string): [string, Uint8Array][];
export function mediaVersion(files: [string, Uint8Array][]): string;
export function readCore(path: string | URL): Uint8Array | undefined;
export function serviceWorker(options: { template: string | URL; version: string }): Plugin;
