import QRCode from 'qrcode';

/**
 * A QR-kód PNG data URL-je, a böngészőben generálva. Korábban egy külső
 * szolgáltatás (api.qrserver.com) állította elő, ami a QR-értékeket egy
 * harmadik félnek is elküldte; a helyi generálás ezt megszünteti.
 * A kültéri matricák miatt 'Q' hibajavítási szint (~25% sérülést tűr).
 */
export const qrDataUrl = (value, size = 140) =>
  QRCode.toDataURL(String(value ?? ''), {
    width: size,
    margin: 1,
    errorCorrectionLevel: 'Q',
  });
