import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';
import { paymentSummary, type WorkOrder } from './database';

const escape = (value: string) => value.replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char] ?? char);
const money = (cents: number) => new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(cents / 100);

export async function shareOrderPdf(order: WorkOrder) {
  const payment = paymentSummary(order);
  const rows = order.lines.map(line => `<tr><td>${escape(line.concept)}</td><td>${line.quantity}</td><td>${money(line.unitPriceCents)}</td><td>${money(Math.round(line.quantity * line.unitPriceCents))}</td></tr>`).join('');
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>body{font-family:Arial;padding:30px;color:#1b2420}h1{color:#0e5e4a}table{width:100%;border-collapse:collapse}td,th{padding:9px;border-bottom:1px solid #ddd;text-align:left}.total{text-align:right;font-size:22px;font-weight:bold}.legal{margin-top:40px;color:#666;font-size:12px}</style></head><body><h1>Jale · Nota de servicio</h1><p><b>Folio:</b> ${escape(order.id.slice(-10).toUpperCase())}<br><b>Cliente:</b> ${escape(order.clientName)}<br><b>Fecha:</b> ${new Date().toLocaleString('es-MX')}</p><table><thead><tr><th>Concepto</th><th>Cant.</th><th>Precio</th><th>Importe</th></tr></thead><tbody>${rows}</tbody></table><p class="total">Total: ${money(order.totalCents)}</p><p><b>Pagado:</b> ${money(payment.paidCents)}<br><b>Saldo:</b> ${money(payment.balanceCents)}<br><b>Estado:</b> ${escape(payment.status)}<br><b>Notas:</b> ${escape(order.notes || 'Sin notas')}</p><p class="legal">Este documento no es un comprobante fiscal.</p></body></html>`;
  const { uri } = await Print.printToFileAsync({ html });
  if (!(await Sharing.isAvailableAsync())) throw new Error('La función de compartir no está disponible en este dispositivo.');
  await Sharing.shareAsync(uri, { mimeType: 'application/pdf', dialogTitle: 'Compartir nota de servicio', UTI: 'com.adobe.pdf' });
  return uri;
}
