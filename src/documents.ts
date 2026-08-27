import { File } from 'expo-file-system';
import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';
import type { BusinessProfile, Payment, Quote } from './domain';
import { formatFolio, money, normalizeBrandColor, paymentSummary } from './domain';

const escapeHtml = (value: string) => value.replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char] ?? char);
const date = (value: string) => new Date(/^\d{4}-\d{2}-\d{2}$/.test(value) ? `${value}T12:00:00Z` : value).toLocaleDateString('es-MX', { day: 'numeric', month: 'long', year: 'numeric' });

async function logoDataUri(profile: BusinessProfile, isPro: boolean) {
  if (!isPro || !profile.logoUri) return '';
  const file = new File(profile.logoUri); if (!file.exists) return '';
  const base64 = await file.base64();
  const mimeType = base64.startsWith('/9j/') ? 'image/jpeg' : base64.startsWith('iVBOR') ? 'image/png' : '';
  return mimeType ? `data:${mimeType};base64,${base64}` : '';
}

function shell(profile: BusinessProfile, isPro: boolean, body: string, logo: string) {
  const accent = isPro ? normalizeBrandColor(profile.brandColor) : '#0E5E4A';
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    @page{margin:24px}body{font-family:Arial,sans-serif;color:#17221d;font-size:12px;margin:0}.header{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:3px solid ${accent};padding-bottom:16px;margin-bottom:22px}.logo{max-width:100px;max-height:70px}.business{font-size:23px;font-weight:800;color:${accent}}.muted{color:#69746f}.meta{line-height:1.6;text-align:right}h1{font-size:18px;margin:0 0 5px}table{width:100%;border-collapse:collapse;margin:20px 0}th{background:#f1f5f3;color:${accent};font-size:10px;text-transform:uppercase}td,th{padding:10px 7px;border-bottom:1px solid #dfe5e2;text-align:left}.number{text-align:right}.total{font-size:22px;font-weight:800;text-align:right;color:${accent}}.box{border:1px solid #dfe5e2;border-radius:8px;padding:12px;margin-top:14px}.legal{margin-top:36px;border-top:1px solid #ddd;padding-top:10px;font-size:10px;color:#777}.jale{text-align:center;margin-top:14px;color:#777;font-size:10px}</style></head><body>
    <div class="header"><div>${logo ? `<img class="logo" src="${logo}">` : ''}<div class="business">${escapeHtml(profile.name)}</div><div class="muted">${escapeHtml(profile.trade)}${profile.phone ? ` · ${escapeHtml(profile.phone)}` : ''}</div></div>${body.split('<!--META-->')[0]}</div>${body.split('<!--META-->')[1]}
    <div class="legal">Este documento no es un comprobante fiscal.</div>${isPro ? '' : '<div class="jale">Creado con Jale</div>'}</body></html>`;
}

export async function quoteHtml(profile: BusinessProfile, quote: Quote, isPro: boolean) {
  const rows = quote.lines.map(line => `<tr><td>${escapeHtml(line.concept)}</td><td class="number">${line.quantity}</td><td class="number">${money(line.unitPriceCents)}</td><td class="number">${money(Math.round(line.quantity * line.unitPriceCents))}</td></tr>`).join('');
  const meta = `<div class="meta"><h1>COTIZACIÓN</h1><b>${formatFolio('COT', quote.quoteNumber)}</b><br>${date(quote.issuedAt)}${quote.validUntil ? `<br>Válida hasta ${date(quote.validUntil)}` : ''}</div>`;
  const content = `<section><b>Cliente</b><br>${escapeHtml(quote.clientName)}</section><table><thead><tr><th>Concepto</th><th class="number">Cant.</th><th class="number">Precio</th><th class="number">Importe</th></tr></thead><tbody>${rows}</tbody></table><div class="total">Total: ${money(quote.totalCents)}</div>${quote.notes ? `<div class="box"><b>Notas</b><br>${escapeHtml(quote.notes)}</div>` : ''}`;
  return shell(profile, isPro, `${meta}<!--META-->${content}`, await logoDataUri(profile, isPro));
}

export async function receiptHtml(profile: BusinessProfile, quote: Quote, payment: Payment, isPro: boolean) {
  const summary = paymentSummary(quote.totalCents, quote.payments);
  const meta = `<div class="meta"><h1>RECIBO DE PAGO</h1><b>${formatFolio('REC', payment.receiptNumber)}</b><br>${date(payment.paidAt)}</div>`;
  const method = payment.method === 'cash' ? 'Efectivo' : payment.method === 'transfer' ? 'Transferencia' : 'Otro';
  const content = `<section><b>Recibimos de</b><br>${escapeHtml(quote.clientName)}</section><div class="box"><b>Por concepto de</b><br>Pago de ${formatFolio('COT', quote.quoteNumber)}${payment.notes ? ` · ${escapeHtml(payment.notes)}` : ''}</div><p>Forma de pago: <b>${method}</b></p><div class="total">Recibido: ${money(payment.amountCents)}</div><div class="box">Total de la cotización: ${money(quote.totalCents)}<br>Pagado acumulado: ${money(summary.paidCents)}<br><b>Saldo pendiente: ${money(summary.balanceCents)}</b></div>`;
  return shell(profile, isPro, `${meta}<!--META-->${content}`, await logoDataUri(profile, isPro));
}

async function shareHtml(html: string, title: string) {
  const { uri } = await Print.printToFileAsync({ html });
  if (!(await Sharing.isAvailableAsync())) throw new Error('La función de compartir no está disponible.');
  await Sharing.shareAsync(uri, { mimeType: 'application/pdf', UTI: 'com.adobe.pdf', dialogTitle: title });
  return uri;
}

export async function shareQuotePdf(profile: BusinessProfile, quote: Quote, isPro: boolean) { return shareHtml(await quoteHtml(profile, quote, isPro), `Compartir ${formatFolio('COT', quote.quoteNumber)}`); }
export async function shareReceiptPdf(profile: BusinessProfile, quote: Quote, payment: Payment, isPro: boolean) { return shareHtml(await receiptHtml(profile, quote, payment, isPro), `Compartir ${formatFolio('REC', payment.receiptNumber)}`); }
