/**
 * Passes a code on once while it stays in view: the camera reports the same barcode many times a second. A different
 * code in between lets it through again, as ScanSheet's Coordinator does with its lastCode on iOS.
 */
export class NewCodes {
  private last?: string;

  accept(code: string): boolean {
    if (code === this.last) return false;
    this.last = code;
    return true;
  }
}
