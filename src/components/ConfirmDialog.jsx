import React from 'react';
import '../styles/ConfirmDialog.css';

export const ConfirmDialog = ({ title, message, onClose, actions = [] }) => {
  return (
    <div className="confirm-dialog-overlay">
      <div className="confirm-dialog">
        <div className="confirm-header">
          <h2>{title}</h2>
          <button className="confirm-close" onClick={onClose}>✕</button>
        </div>

        {message && <p className="confirm-message">{message}</p>}

        <div className="confirm-actions">
          {actions.map((action, index) => (
            <button
              key={index}
              onClick={() => {
                action.onClick();
                onClose();
              }}
              className="confirm-action-btn"
            >
              {action.label}
            </button>
          ))}
          <button onClick={onClose} className="confirm-cancel-btn">
            Mégsem
          </button>
        </div>
      </div>
    </div>
  );
};
