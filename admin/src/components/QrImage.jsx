import PropTypes from 'prop-types';
import { useEffect, useState } from 'react';
import { qrDataUrl } from '../utils/qrHelpers';

/** Helyben generált QR-kép. Amíg a kép elkészül, üres helyet foglal. */
export default function QrImage({ value, size = 140, alt, className }) {
  const [src, setSrc] = useState('');

  useEffect(() => {
    let cancelled = false;
    qrDataUrl(value, size)
      .then((url) => { if (!cancelled) setSrc(url); })
      .catch(() => { if (!cancelled) setSrc(''); });
    return () => { cancelled = true; };
  }, [value, size]);

  if (!src) return <span className={className} style={{ display: 'inline-block', width: size, height: size }} aria-label={alt} />;
  return <img src={src} alt={alt} width={size} height={size} className={className} />;
}

QrImage.propTypes = {
  value: PropTypes.string.isRequired,
  size: PropTypes.number,
  alt: PropTypes.string.isRequired,
  className: PropTypes.string,
};
