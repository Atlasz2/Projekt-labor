// Small dependency-free CSV helper used by the admin export buttons.
//
// buildCsv(rows, columns) -> string
//   columns: [{ key, label, format? }]  — format(value, row) is optional.
// downloadCsv(filename, csv) -> triggers a browser download (UTF-8 + BOM so
//   Excel renders Hungarian accents correctly).

const BOM = String.fromCharCode(0xfeff);

const escapeCell = (value) => {
  const text = value == null ? "" : String(value);
  // Quote when the cell contains a delimiter, quote, or newline.
  if (/[",\n\r;]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
};

export function buildCsv(rows, columns) {
  const header = columns.map((col) => escapeCell(col.label)).join(",");
  const lines = (rows ?? []).map((row) =>
    columns
      .map((col) => escapeCell(col.format ? col.format(row[col.key], row) : row[col.key]))
      .join(",")
  );
  return [header, ...lines].join("\r\n");
}

export function downloadCsv(filename, csv) {
  // Prepend a UTF-8 BOM so Excel detects UTF-8 and shows accents correctly.
  const blob = new Blob([BOM + csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
