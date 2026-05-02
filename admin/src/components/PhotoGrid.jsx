import React from "react";
import PropTypes from "prop-types";

export default function PhotoGrid({ photos, uploading, feedback, onUpload, onRemove }) {
  return (
    <div className="editor-upload-box">
      <label>
        Kepek <span className="upload-count">{photos.length}/6</span>
      </label>
      <div className="photo-grid">
        {photos.map((url, index) => (
          <div key={url + index} className="photo-thumb">
            <img src={url} alt="" />
            <button type="button" className="photo-remove" onClick={() => onRemove(index)}>
              x
            </button>
            {index === 0 && <span className="thumb-badge">Boritokep</span>}
          </div>
        ))}
        {photos.length < 6 && (
          <label className="photo-add-btn">
            <input
              type="file"
              accept="image/*"
              disabled={uploading}
              onChange={(event) => {
                if (event.target.files?.[0]) onUpload(event.target.files[0]);
                event.target.value = "";
              }}
            />
            {uploading ? "Feltoltes..." : "+ Kep"}
          </label>
        )}
      </div>
      {feedback.type !== "idle" && (
        <p className={`upload-note upload-note-${feedback.type}`}>{feedback.text}</p>
      )}
    </div>
  );
}

PhotoGrid.propTypes = {
  photos: PropTypes.arrayOf(PropTypes.string).isRequired,
  uploading: PropTypes.bool.isRequired,
  feedback: PropTypes.shape({
    type: PropTypes.string.isRequired,
    text: PropTypes.string,
  }).isRequired,
  onUpload: PropTypes.func.isRequired,
  onRemove: PropTypes.func.isRequired,
};
