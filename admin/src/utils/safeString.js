export const safeString = (val) => {
  if (val === null || val === undefined) return "";
  if (typeof val === "object") return "";
  return String(val).trim();
};
