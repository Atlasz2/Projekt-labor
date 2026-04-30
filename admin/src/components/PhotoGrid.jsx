import React from 'react';

export default function PhotoGrid({ photos, uploading, feedback, onUpload, onRemove }) {
  return (
    <div className="editor-upload-box">
      <label>
        Kepek <span className="upload-count">{photos.length}/6</span>
      </label>
      <div className="photo-grid">
        {photos.map((url, i) => (
          <div key={i} className="photo-thumb">
            <img src={url} alt="" />
            <button type="button" className="photo-remove" onClick={() => onRemove(i)}>
              x
            </button>
            {i === 0 && <span className="thumb-badge">Boritokep</span>}
          </div>
        ))}
        {photos.length < 6 && (
          <label className="photo-add-btn">
            <input
              type="file"
              accept="image/*"
              disabled={uploading}
              onChange={(e) => {
                if (e.target.files?.[0]) onUpload(e.target.files[0]);
                e.target.value = '';
              }}
            />
            {uploading ? 'Feltoltes...' : '+ Kep'}
          </label>
        )}
      </div>
      {feedback.type !== 'idle' && (
        <p className={`upload-note upload-note-${feedback.type}`}>{feedback.text}</p>
      )}
    </div>
  );
}
