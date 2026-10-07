import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("firebase/storage", () => ({
  ref: (_storage, path) => ({ path }),
  uploadBytes: vi.fn(),
  getDownloadURL: vi.fn(),
}));

import { getDownloadURL, uploadBytes } from "firebase/storage";
import { uploadImageWithFallback } from "./imageUpload";

const smallFile = () => new File(["kicsi kép"], "vár fotó (1).jpg", { type: "image/jpeg" });

describe("uploadImageWithFallback", () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => vi.useRealTimers());

  it("Storage-ba tölt, biztonságos fájlnévvel", async () => {
    uploadBytes.mockResolvedValueOnce({ ref: "snapref" });
    getDownloadURL.mockResolvedValueOnce("https://storage/url");
    const res = await uploadImageWithFallback({ file: smallFile(), storage: {}, folder: "stations" });
    expect(res).toMatchObject({ url: "https://storage/url", mode: "storage" });
    const path = uploadBytes.mock.calls[0][0].path;
    expect(path).toMatch(/^stations\/\d+_v_r_fot___1_\.jpg$/);
  });

  it("Storage-hiba esetén beágyazott képre esik vissza, figyelmeztetéssel", async () => {
    uploadBytes.mockRejectedValueOnce(new Error("storage/unauthorized"));
    const res = await uploadImageWithFallback({ file: smallFile(), storage: {}, folder: "stations" });
    expect(res.mode).toBe("inline");
    expect(res.url.startsWith("data:image/jpeg;base64,")).toBe(true);
    expect(res.message).toMatch(/FIGYELEM/);
  });

  it("ha a Storage nem válaszol, 30 másodperc után a tartalékra vált (nem akad el)", async () => {
    vi.useFakeTimers();
    uploadBytes.mockReturnValueOnce(new Promise(() => {})); // soha nem tér vissza
    const pending = uploadImageWithFallback({ file: smallFile(), storage: {}, folder: "stations" });
    await vi.advanceTimersByTimeAsync(30_000);
    await vi.runAllTimersAsync(); // a tartalék fájlolvasása is időzítőn fut
    const res = await pending;
    expect(res.mode).toBe("inline");
  });

  it("fájl nélkül hibát dob", async () => {
    await expect(uploadImageWithFallback({ file: null, storage: {}, folder: "x" })).rejects.toThrow(
      "Nincs kiválasztott fájl.",
    );
  });
});
