import React, { useState, useEffect, useCallback } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs, updateDoc, deleteDoc, doc } from "firebase/firestore";
import {
  Box, Typography, CircularProgress, Alert, Chip, Card, CardContent, CardActions,
  Button, TextField, Select, MenuItem, FormControl, InputLabel, Stack, Divider, Snackbar,
} from "@mui/material";
import DeleteIcon from "@mui/icons-material/Delete";
import CheckCircleIcon from "@mui/icons-material/CheckCircle";
import RadioButtonUncheckedIcon from "@mui/icons-material/RadioButtonUnchecked";
import RefreshIcon from "@mui/icons-material/Refresh";
import ConfirmDialog from "../components/ConfirmDialog";
import StateCard from "../components/StateCard";
import { buildCsv, downloadCsv } from "../utils/exportCsv";

const STATUS_LABEL = { open: "Nyitott", closed: "Lezárt" };

const normalizeStatus = (raw) => {
  if (raw === "closed" || raw === "lezart" || raw === true || raw === "true") return "closed";
  return "open";
};

const fmtDate = (val) => {
  if (!val) return "-";
  try {
    const d = val?.toDate ? val.toDate() : new Date(val);
    return isNaN(d.getTime()) ? "-" : d.toLocaleString("hu-HU");
  } catch { return "-"; }
};

function BugReports() {
  const [reports, setReports] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState(() => localStorage.getItem("admin_br_filter") || "all");
  const [responseInputs, setResponseInputs] = useState({});
  const [savingId, setSavingId] = useState(null);
  const [deleteId, setDeleteId] = useState(null);
  const [snack, setSnack] = useState({ open: false, message: "", severity: "error" });

  const showSnack = useCallback((message, severity = "error") => setSnack({ open: true, message, severity }), []);

  const fetchReports = useCallback(async () => {
    try {
      setLoading(true);
      const snap = await getDocs(collection(db, "bug_reports"));
      const data = snap.docs.map((d) => {
        const raw = d.data();
        return { id: d.id, ...raw, status: normalizeStatus(raw.status) };
      });
      data.sort((a, b) => {
        const ta = a.created_at?.toDate?.() ?? new Date(a.created_at_ms ?? 0);
        const tb = b.created_at?.toDate?.() ?? new Date(b.created_at_ms ?? 0);
        return tb - ta;
      });
      setReports(data);
    } catch (err) {
      showSnack("Betöltési hiba: " + err.message);
    } finally {
      setLoading(false);
    }
  }, [showSnack]);

  useEffect(() => {
    const t = setTimeout(() => void fetchReports(), 0);
    return () => clearTimeout(t);
  }, [fetchReports]);

  const handleDelete = async () => {
    if (!deleteId) return;
    const id = deleteId;
    setDeleteId(null);
    try {
      await deleteDoc(doc(db, "bug_reports", id));
      setReports((prev) => prev.filter((r) => r.id !== id));
      showSnack("Hibajelentés törölve.", "success");
    } catch (err) {
      showSnack("Törlési hiba: " + err.message);
    }
  };

  const handleToggleStatus = async (report) => {
    const newStatus = report.status === "closed" ? "open" : "closed";
    try {
      await updateDoc(doc(db, "bug_reports", report.id), { status: newStatus });
      setReports((prev) => prev.map((r) => r.id === report.id ? { ...r, status: newStatus } : r));
      showSnack(newStatus === "closed" ? "Hibajelentés lezárva." : "Hibajelentés újranyitva.", "success");
    } catch (err) {
      showSnack("Frissítési hiba: " + err.message);
    }
  };

  const handleSaveResponse = async (report) => {
    const resp = (responseInputs[report.id] ?? report.admin_response ?? "").trim();
    if (!resp) return;
    setSavingId(report.id);
    try {
      await updateDoc(doc(db, "bug_reports", report.id), { admin_response: resp });
      setReports((prev) => prev.map((r) => r.id === report.id ? { ...r, admin_response: resp } : r));
      setResponseInputs((prev) => { const n = { ...prev }; delete n[report.id]; return n; });
      showSnack("Válasz mentve.", "success");
    } catch (err) {
      showSnack("Mentési hiba: " + err.message);
    } finally {
      setSavingId(null);
    }
  };

  const filtered = filter === "all" ? reports : reports.filter((r) => normalizeStatus(r.status) === filter);

  const handleExportCsv = () => {
    const columns = [
      { key: "title", label: "Cím", format: (v) => v || "(Cím nélkül)" },
      { key: "status", label: "Státusz", format: (v) => STATUS_LABEL[normalizeStatus(v)] },
      { key: "description", label: "Leírás" },
      { key: "reported_by", label: "Bejelentő neve", format: (v) => v?.name || "" },
      { key: "reported_by", label: "Bejelentő email", format: (v) => v?.email || "" },
      { key: "admin_response", label: "Admin válasz" },
      { key: "created_at", label: "Beküldve", format: (v, row) => fmtDate(v ?? row.created_at_text) },
    ];
    const today = new Date().toISOString().slice(0, 10);
    downloadCsv(`hibajelentesek_${today}.csv`, buildCsv(filtered, columns));
    showSnack(`${filtered.length} hibajelentés exportálva CSV-be.`, "success");
  };

  return (
    <Box sx={{ p: 3, maxWidth: 960, mx: "auto" }}>
      <Box sx={{ mb: 4, pb: 3, borderBottom: "1px solid", borderColor: "divider" }}>
        <Typography variant="overline" sx={{ color: "primary.main", letterSpacing: "0.15em", fontWeight: 700, fontSize: "0.7rem" }}>
          Adminisztráció
        </Typography>
        <Typography variant="h4" fontWeight={800} color="text.primary" sx={{ mt: 0.5, mb: 0.75, letterSpacing: "-0.02em" }}>
          Hibabejelentések
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2.5 }}>
          Felhasználók által beküldött hibajelentések kezelése és megválaszolása.
        </Typography>
        <Stack direction="row" gap={1.5} flexWrap="wrap">
          {[
            { label: "Összes", value: reports.length, bg: "#eff6ff", darkBg: "rgba(37,99,235,0.15)", color: "#2563eb", darkColor: "#60a5fa", border: "rgba(37,99,235,0.2)", darkBorder: "rgba(96,165,250,0.35)" },
            { label: "Nyitott", value: reports.filter(r => normalizeStatus(r.status) === "open").length, bg: "#fef2f2", darkBg: "rgba(220,38,38,0.15)", color: "#dc2626", darkColor: "#fca5a5", border: "rgba(220,38,38,0.2)", darkBorder: "rgba(248,113,113,0.35)" },
            { label: "Lezárt", value: reports.filter(r => normalizeStatus(r.status) === "closed").length, bg: "#f0fdf4", darkBg: "rgba(5,150,105,0.15)", color: "#059669", darkColor: "#6ee7b7", border: "rgba(5,150,105,0.2)", darkBorder: "rgba(110,231,183,0.3)" },
          ].map(({ label, value, bg, darkBg, color, darkColor, border, darkBorder }) => (
            <Box key={label} sx={{ px: 2.5, py: 1.25, borderRadius: 2, bgcolor: (t) => t.palette.mode === "dark" ? darkBg : bg, border: (t) => `1px solid ${t.palette.mode === "dark" ? darkBorder : border}` }}>
              <Typography variant="h5" fontWeight={800} sx={{ color: (t) => t.palette.mode === "dark" ? darkColor : color, lineHeight: 1.1 }}>{value}</Typography>
              <Typography variant="caption" sx={{ color: (t) => t.palette.mode === "dark" ? darkColor : color, fontWeight: 600, opacity: 0.85 }}>{label}</Typography>
            </Box>
          ))}
        </Stack>
      </Box>

      {loading ? (
        <StateCard variant="loading" icon="🐛" title="Hibajelentések betöltése..." description="Kérjük várj, az adatok betöltése folyamatban van." />
      ) : (
        <>
          <Stack direction="row" gap={2} alignItems="center" mb={3} flexWrap="wrap">
            <FormControl size="small" sx={{ minWidth: 150 }}>
              <InputLabel>Szűrő</InputLabel>
              <Select value={filter} label="Szűrő" onChange={(e) => { setFilter(e.target.value); localStorage.setItem("admin_br_filter", e.target.value); }}>
                <MenuItem value="all">Összes ({reports.length})</MenuItem>
                <MenuItem value="open">Nyitott ({reports.filter(r => normalizeStatus(r.status) === "open").length})</MenuItem>
                <MenuItem value="closed">Lezárt ({reports.filter(r => normalizeStatus(r.status) === "closed").length})</MenuItem>
              </Select>
            </FormControl>
            <Button variant="outlined" startIcon={<RefreshIcon />} onClick={fetchReports} size="small">Frissítés</Button>
            <Button variant="outlined" onClick={handleExportCsv} size="small" disabled={filtered.length === 0}>⬇ CSV</Button>
          </Stack>

          {filtered.length === 0 ? (
            <StateCard
              variant="empty"
              icon="🐛"
              title="Nincs hibajelentés"
              description={filter !== "all" ? `Nincs ${STATUS_LABEL[filter]?.toLowerCase()} hibajelentés.` : "Még nem érkezett be hibajelentés."}
            />
          ) : (
            <Stack gap={2}>
              {filtered.map((r) => {
                const status = normalizeStatus(r.status);
                return (
                <Card key={r.id} variant="outlined" sx={{ borderLeft: "4px solid", borderLeftColor: status === "closed" ? "grey.400" : "primary.main" }}>
                  <CardContent>
                    <Stack direction="row" alignItems="flex-start" justifyContent="space-between" gap={2} flexWrap="wrap">
                      <Box flex={1}>
                        <Typography variant="subtitle1" fontWeight={700}>{r.title || "(Cím nélkül)"}</Typography>
                        <Stack direction="row" gap={1} mt={0.5} flexWrap="wrap">
                          <Chip label={STATUS_LABEL[status]} size="small" variant={status === "closed" ? "outlined" : "filled"} />
                          <Typography variant="caption" color="text.secondary" sx={{ alignSelf: "center" }}>
                            {fmtDate(r.created_at ?? r.created_at_text)}
                          </Typography>
                        </Stack>
                      </Box>
                      <Box>
                        <Typography variant="caption" color="text.secondary">
                          {r.reported_by?.name ? `${r.reported_by.name} \u2022 ` : ""}{r.reported_by?.email ?? ""}{r.reported_by?.os ? ` \u2022 ${r.reported_by.os}` : ""}
                        </Typography>
                      </Box>
                    </Stack>

                    <Typography variant="body2" mt={1.5} sx={{ whiteSpace: "pre-wrap" }}>{r.description}</Typography>

                    {r.admin_response && responseInputs[r.id] === undefined && (
                      <Box mt={1.5} p={1.5} sx={{ bgcolor: (t) => t.palette.mode === "dark" ? "rgba(37,99,235,0.12)" : "#f0f7ff", borderRadius: 2, borderLeft: "3px solid #2563eb" }}>
                        <Typography variant="caption" color="text.secondary" fontWeight={600}>Admin válasz:</Typography>
                        <Typography variant="body2">{r.admin_response}</Typography>
                      </Box>
                    )}

                    <Box mt={2}>
                      <TextField
                        fullWidth
                        size="small"
                        multiline
                        minRows={2}
                        label="Admin válasz"
                        value={responseInputs[r.id] ?? r.admin_response ?? ""}
                        onChange={(e) => setResponseInputs((prev) => ({ ...prev, [r.id]: e.target.value }))}
                        placeholder="Válasz a felhasználónak..."
                      />
                    </Box>
                  </CardContent>

                  <Divider />
                  <CardActions sx={{ px: 2 }}>
                    <Button size="small" startIcon={status === "closed" ? <RadioButtonUncheckedIcon /> : <CheckCircleIcon />} onClick={() => handleToggleStatus(r)}>
                      {status === "closed" ? "Újranyitás" : "Lezárás"}
                    </Button>
                    {(responseInputs[r.id] !== undefined && responseInputs[r.id] !== (r.admin_response ?? "")) && (
                      <Button
                        size="small"
                        variant="contained"
                        disabled={savingId === r.id}
                        startIcon={savingId === r.id ? <CircularProgress size={14} color="inherit" /> : null}
                        onClick={() => handleSaveResponse(r)}
                      >
                        Válasz mentése
                      </Button>
                    )}
                    <Box flex={1} />
                    <Button size="small" color="error" startIcon={<DeleteIcon />} onClick={() => setDeleteId(r.id)}>Törlés</Button>
                  </CardActions>
                </Card>
                );
              })}
            </Stack>
          )}
        </>
      )}

      <ConfirmDialog
        open={deleteId !== null}
        title="Hibajelentés törlése"
        message="Biztosan törli ezt a hibajelentést? Ez a művelet nem vonható vissza."
        confirmText="Törlés"
        onConfirm={handleDelete}
        onClose={() => setDeleteId(null)}
      />

      <Snackbar
        open={snack.open}
        autoHideDuration={4000}
        onClose={() => setSnack((s) => ({ ...s, open: false }))}
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
      >
        <Alert severity={snack.severity} onClose={() => setSnack((s) => ({ ...s, open: false }))} sx={{ width: "100%" }}>
          {snack.message}
        </Alert>
      </Snackbar>
    </Box>
  );
}

export default BugReports;




