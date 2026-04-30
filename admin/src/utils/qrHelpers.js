export const getQrValue = (item) => item.qrCode || item.id;

export const getQrImageUrl = (value, size = 140) =>
  `https://api.qrserver.com/v1/create-qr-code/?size=${size}x${size}&data=${encodeURIComponent(value || '')}`;
