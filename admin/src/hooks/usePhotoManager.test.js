import { act, renderHook } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("firebase/storage", () => ({
  ref: (_storage, url) => ({ url }),
  deleteObject: vi.fn(async () => {}),
}));
vi.mock("../utils/imageUpload", () => ({ uploadImageWithFallback: vi.fn() }));

import { deleteObject } from "firebase/storage";
import { uploadImageWithFallback } from "../utils/imageUpload";
import { usePhotoManager } from "./usePhotoManager";

const STORAGE_URL = "https://firebasestorage.googleapis.com/v0/b/x/o/stations%2Fa.jpg";
const INLINE_URL = "data:image/jpeg;base64,AAAA";

const setup = (initial) => {
  const hook = renderHook(() => usePhotoManager({ storage: {}, folder: "stations" }));
  if (initial) act(() => hook.result.current.reset(initial));
  return hook;
};

describe("usePhotoManager", () => {
  beforeEach(() => vi.clearAllMocks());

  it("az eltávolított Storage-kép csak a mentés utáni commitRemovals-kor törlődik", async () => {
    const { result } = setup([STORAGE_URL, INLINE_URL]);
    act(() => result.current.remove(0));
    expect(result.current.photos).toEqual([INLINE_URL]);
    expect(deleteObject).not.toHaveBeenCalled();

    await act(() => result.current.commitRemovals());
    expect(deleteObject).toHaveBeenCalledTimes(1);
    expect(deleteObject).toHaveBeenCalledWith({ url: STORAGE_URL });
  });

  it("megszakított szerkesztésnél (reset) semmi nem törlődik", async () => {
    const { result } = setup([STORAGE_URL]);
    act(() => result.current.remove(0));
    act(() => result.current.reset([STORAGE_URL]));
    await act(() => result.current.commitRemovals());
    expect(deleteObject).not.toHaveBeenCalled();
    expect(result.current.photos).toEqual([STORAGE_URL]);
  });

  it("a beágyazott (nem Storage) kép eltávolítása nem indít Storage-törlést", async () => {
    const { result } = setup([INLINE_URL]);
    act(() => result.current.remove(0));
    await act(() => result.current.commitRemovals());
    expect(deleteObject).not.toHaveBeenCalled();
  });

  it("a Storage-törlés hibája nem akasztja meg a többit", async () => {
    const second = STORAGE_URL.replace("a.jpg", "b.jpg");
    deleteObject.mockRejectedValueOnce(new Error("already deleted"));
    const { result } = setup([STORAGE_URL, second]);
    act(() => result.current.remove(0));
    act(() => result.current.remove(0));
    await act(() => result.current.commitRemovals());
    expect(deleteObject).toHaveBeenCalledTimes(2);
  });

  it("feltöltés után a kép a listába kerül, és visszajelzést ad", async () => {
    uploadImageWithFallback.mockResolvedValueOnce({ url: STORAGE_URL, message: "Kép feltöltve." });
    const { result } = setup();
    await act(() => result.current.upload(new File(["x"], "a.jpg")));
    expect(result.current.photos).toEqual([STORAGE_URL]);
    expect(result.current.uploadFeedback).toEqual({ type: "success", text: "Kép feltöltve." });
    expect(result.current.uploading).toBe(false);
  });

  it("legfeljebb hat kép tölthető fel", async () => {
    const { result } = setup(Array.from({ length: 6 }, (_, i) => `${STORAGE_URL}${i}`));
    await act(() => result.current.upload(new File(["x"], "hetedik.jpg")));
    expect(uploadImageWithFallback).not.toHaveBeenCalled();
    expect(result.current.uploadFeedback.type).toBe("error");
  });

  it("sikertelen feltöltésnél hibaüzenet, a lista változatlan", async () => {
    uploadImageWithFallback.mockRejectedValueOnce(new Error("A kép túl nagy."));
    const { result } = setup();
    await act(() => result.current.upload(new File(["x"], "nagy.jpg")));
    expect(result.current.photos).toEqual([]);
    expect(result.current.uploadFeedback).toEqual({ type: "error", text: "A kép túl nagy." });
  });
});
