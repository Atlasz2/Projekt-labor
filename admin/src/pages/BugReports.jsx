import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs, updateDoc, deleteDoc, doc, orderBy, query } from "firebase/firestore";
import { Box, Typography, CircularProgress, Alert, Chip, Card, CardContent, CardActions, Button, TextField, Select, MenuItem, FormControl, InputLabel, Stack, Divider } from "@mui/material";
import DeleteIcon from "@mui/icons-material/Delete";
import CheckCircleIcon from "@mui/icons-material/CheckCircle";
import RadioButtonUncheckedIcon from "@mui/icons-material/RadioButtonUnchecked";
import RefreshIcon from "@mui/icons-material/Refresh";

const SEVERITY_LABEL = { low: "Alacsony", medium: "Közepes", high: "Magas" };
const SEVERITY_COLOR = { low: "success", medium: "warning", high: "error" };
const STATUS_LABEL = { open: "Nyitott", closed: "Lezárt" };

const normalizeStatus = (raw) => {
  if (raw === "closed" || raw === "lezart" || raw === true || raw === "true") return "closed";
  return "open";
};

const fmtDate = (val) => {
  if (!val) return "–";
  try {
    const d = val?.toDate ? val.toDate() : new Date(val);
    return isNaN(d.getTime()) ? "–" : d.toLocaleString("hu-HU");
  } catch { return "–"; }
};

function BugReports() {
  const [reports, setReports] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filter, setFilter] = useState(() => localStorage.getItem('admin_br_filter') || 'all');
  const [responseInputs, setResponseInputs] = useState({});

  useEffect(() => { fetchReports(); }, []);

  const fetchReports = async () => {
    try {
      setLoading(true);
      setError(null);
      const q = query(collection(db, "bug_reports"));
      const snap = await getDocs(q);
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
      setError("Betöltési hiba: " + err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (id) => {
    if (!window.confirm("Biztosan törli ezt a hibajelentést?")) return;
    try {
      await deleteDoc(doc(db, "bug_reports", id));
      setReports((prev) => prev.filter((r) => r.id !== id));
    } catch (err) {
      alert("Törlési hiba: " + err.message);
    }
  };

  const handleToggleStatus = async (report) => {
    const newStatus = report.status === "closed" ? "open" : "closed";
    try {
      await updateDoc(doc(db, "bug_reports", report.id), { status: newStatus });
      setReports((prev) => prev.map((r) => r.id === report.id ? { ...r, status: newStatus } : r));
    } catch (err) {
      alert("Frissítési hiba: " + err.message);
    }
  };

  const handleSaveResponse = async (report) => {
    const resp = responseInputs[report.id] ?? report.admin_response ?? "";
    try {
      await updateDoc(doc(db, "bug_reports", report.id), { admin_response: resp });
      setReports((prev) => prev.map((r) => r.id === report.id ? { ...r, admin_response: resp } : r));
      setResponseInputs((prev) => { const n = { ...prev }; delete n[report.id]; return n; });
    } catch (err) {
      alert("Mentési hiba: " + err.message);
    }
  };

  const filtered = filter === "all" ? reports : reports.filter((r) => normalizeStatus(r.status) === filter);

  if (loading) return <Box sx={{ display: "flex", justifyContent: "center", mt: 8 }}><CircularProgress /></Box>;
  if (error) return <Alert severity="error" sx={{ m: 3 }}>{error}</Alert>;

  return (
    <Box sx={{ p: 3, maxWidth: 960, mx: "auto" }}>
      <Stack direction="row" alignItems="center" justifyContent="space-between" mb={3} flexWrap="wrap" gap={2}>
        <Typography variant="h5" fontWeight={700}>Hibajelentések ({reports.length})</Typography>
        <Stack direction="row" gap={2} alignItems="center">
          <FormControl size="small" sx={{ minWidth: 150 }}>
            <InputLabel>Szűrő</InputLabel>
            <Select value={filter} label="Szűrő" onChange={(e) => { setFilter(e.target.value); localStorage.setItem('admin_br_filter', e.target.value); }}>
              <MenuItem value="all">Összes ({reports.length})</MenuItem>
              <MenuItem value="open">Nyitott ({reports.filter(r => normalizeStatus(r.status) === "open").length})</MenuItem>
              <MenuItem value="closed">Lezárt ({reports.filter(r => normalizeStatus(r.status) === "closed").length})</MenuItem>
            </Select>
          </FormControl>
          <Button variant="outlined" startIcon={<RefreshIcon />} onClick={fetchReports} size="small">Frissítés</Button>
        </Stack>
      </Stack>

      {filtered.length === 0 && (
        <Alert severity="info">Nincs {filter !== "all" ? STATUS_LABEL[filter]?.toLowerCase() : ""} hibajelentés.</Alert>
      )}

      <Stack gap={2}>
        {filtered.map((r) => (
          <Card key={r.id} variant="outlined" sx={{ borderLeft: `4px solid`, borderLeftColor: normalizeStatus(r.status) === "closed" ? "grey.400" : SEVERITY_COLOR[r.severity] === "error" ? "error.main" : SEVERITY_COLOR[r.severity] === "warning" ? "warning.main" : "success.main" }}>
            <CardContent>
              <Stack direction="row" alignItems="flex-start" justifyContent="space-between" gap={2} flexWrap="wrap">
                <Box flex={1}>
                  <Typography variant="subtitle1" fontWeight={700}>{r.title || "(Cím nélkül)"}</Typography>
                  <Stack direction="row" gap={1} mt={0.5} flexWrap="wrap">
                    <Chip label={SEVERITY_LABEL[r.severity] ?? r.severity ?? "?"} color={SEVERITY_COLOR[r.severity] ?? "default"} size="small" />
                    <Chip label={STATUS_LABEL[normalizeStatus(r.status)]} size="small" variant={normalizeStatus(r.status) === "closed" ? "outlined" : "filled"} />
                    <Typography variant="caption" color="text.secondary" sx={{ alignSelf: "center" }}>
                      {fmtDate(r.created_at ?? r.created_at_text)}
                    </Typography>
                  </Stack>
                </Box>
                <Box>
                  <Typography variant="caption" color="text.secondary">
                    {r.reported_by?.name ? `${r.reported_by.name} • ` : ""}{r.reported_by?.email ?? ""}{r.reported_by?.os ? ` • ${r.reported_by.os}` : ""}
                  </Typography>
                </Box>
              </Stack>

              <Typography variant="body2" mt={1.5} sx={{ whiteSpace: "pre-wrap" }}>{r.description}</Typography>

              {r.admin_response && responseInputs[r.id] === undefined && (
                <Box mt={1.5} p={1.5} bgcolor="grey.50" borderRadius={1}>
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
              <Button size="small" startIcon={normalizeStatus(r.status) === "closed" ? <RadioButtonUncheckedIcon /> : <CheckCircleIcon />} onClick={() => handleToggleStatus(r)}>
                {normalizeStatus(r.status) === "closed" ? "Újranyitás" : "Lezárás"}
              </Button>
              {(responseInputs[r.id] !== undefined && responseInputs[r.id] !== (r.admin_response ?? "")) && (
                <Button size="small" variant="contained" onClick={() => handleSaveResponse(r)}>Válasz mentése</Button>
              )}
              <Box flex={1} />
              <Button size="small" color="error" startIcon={<DeleteIcon />} onClick={() => handleDelete(r.id)}>Törlés</Button>
            </CardActions>
          </Card>
        ))}
      </Stack>
    </Box>
  );
}

export default BugReports;