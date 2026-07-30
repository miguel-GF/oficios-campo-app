import React, { useEffect, useMemo, useState } from 'react';
import {
  Alert, Modal, Pressable, SafeAreaView, ScrollView, StatusBar,
  StyleSheet, Text, TextInput, View,
} from 'react-native';
import { SQLiteProvider, useSQLiteContext } from 'expo-sqlite';
import { CameraCapture } from './src/CameraCapture';
import { closeOrder, createAppointment, isOrderClosed, listAppointments, migrateDatabase, queueCount, saveAttachment } from './src/database';

type Tab = 'Hoy' | 'Agenda' | 'Orden' | 'Clientes';
type Visit = { time: string; name: string; service: string; zone: string; overdue?: boolean };
type Line = { id: number; concept: string; price: number };
type Appointment = { id: string; time: string; name: string; service: string };

const C = { petrol: '#0E5E4A', dark: '#0A4436', soft: '#E3EFEA', ink: '#1B2420', muted: '#6B7570', paper: '#F7F5F0', white: '#FFF', amber: '#E8A13D', line: '#E4E1D8', clay: '#C24F3A' };
const visits: Visit[] = [
  { time: '10:00', name: 'Sra. Martha López', service: 'Fumigación general', zone: 'Col. del Valle' },
  { time: '13:00', name: 'Taquería El Güero', service: 'Control mensual de plagas', zone: 'Roma Nte.' },
  { time: 'Ayer', name: 'Oficina Coyoacán', service: 'Orden pendiente de cerrar', zone: 'Coyoacán', overdue: true },
];
const clients: Array<[string, string, string]> = [
  ['Martha López', 'le toca visita el 29 oct', '$4,350 · 7 visitas'],
  ['Oficina Coyoacán', 'saldo pendiente $500', '$12,800 · 11 visitas'],
  ['Taquería El Güero', 'último servicio: hace 28 días', '$9,600 · 12 visitas'],
  ['Raúl Vega', 'cliente nuevo · jue 30, 11:00', '0 visitas'],
];

export default function App() {
  return <SQLiteProvider databaseName="jale.db" onInit={migrateDatabase}><AppContent /></SQLiteProvider>;
}

function AppContent() {
  const db = useSQLiteContext();
  const [tab, setTab] = useState<Tab>('Hoy');
  const [voice, setVoice] = useState(false);
  const [appointment, setAppointment] = useState(false);
  const [query, setQuery] = useState('');
  const [lines, setLines] = useState<Line[]>([
    { id: 1, concept: 'Fumigación general', price: 800 },
    { id: 2, concept: 'Gel para cucarachas (cocina)', price: 150 },
  ]);
  const [payment, setPayment] = useState('Efectivo');
  const [followup, setFollowup] = useState('3 meses');
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [completed, setCompleted] = useState(false);
  const [localChanges, setLocalChanges] = useState(0);
  const [cameraKind, setCameraKind] = useState<'before' | 'after' | null>(null);
  const total = useMemo(() => lines.reduce((sum, line) => sum + Math.max(0, line.price), 0), [lines]);

  useEffect(() => {
    Promise.all([listAppointments(db), isOrderClosed(db), queueCount(db)]).then(([saved, closed, pending]) => {
      setAppointments(saved); setCompleted(closed); setLocalChanges(pending);
    }).catch(() => Alert.alert('Base local no disponible', 'Reinicia la aplicación para volver a intentarlo.'));
  }, [db]);

  const begin = (visit: Visit) => {
    setTab('Orden');
    setLocalChanges(value => value + 1);
    Alert.alert('Visita iniciada', `${visit.name} quedó en curso y disponible sin conexión.`);
  };

  return (
    <SafeAreaView style={s.safe}>
      <StatusBar barStyle="dark-content" backgroundColor={C.paper} />
      <View style={s.header}>
        <View><Text style={s.eyebrow}>FUMIGACIONES LÓPEZ</Text><Text style={s.title}>{tab}</Text></View>
        <View style={[s.sync, localChanges > 0 && s.syncPending]}><Text style={[s.syncText, localChanges > 0 && s.syncPendingText]}>{localChanges > 0 ? `◷ ${localChanges} local${localChanges === 1 ? '' : 'es'}` : '✓ Modo local'}</Text></View>
      </View>

      {tab === 'Hoy' && <Today onBegin={begin} completed={completed} />}
      {tab === 'Agenda' && <Agenda onAdd={() => setAppointment(true)} appointments={appointments} />}
      {tab === 'Orden' && <Order lines={lines} setLines={setLines} total={total} payment={payment} setPayment={setPayment} followup={followup} setFollowup={setFollowup} onPhoto={setCameraKind} onClose={async () => { await closeOrder(db, Math.round(total * 100), payment, followup); setCompleted(true); setLocalChanges(await queueCount(db)); setTab('Hoy'); }} />}
      {tab === 'Clientes' && <Clients query={query} setQuery={setQuery} />}

      {tab !== 'Orden' && <Pressable accessibilityLabel="Abrir asistente de voz" style={s.fab} onPress={() => setVoice(true)}><Text style={s.fabIcon}>🎙</Text></Pressable>}
      <View style={s.nav}>{(['Hoy', 'Agenda', 'Orden', 'Clientes'] as Tab[]).map((item, i) => <Pressable key={item} style={s.navItem} onPress={() => setTab(item)}><Text style={[s.navIcon, tab === item && s.navOn]}>{['☀', '▦', '▤', '●'][i]}</Text><Text style={[s.navText, tab === item && s.navOn]}>{item}</Text></Pressable>)}</View>

      <VoiceModal open={voice} close={() => setVoice(false)} confirm={() => { setVoice(false); setTab('Agenda'); Alert.alert('Cita guardada', 'Jueves 30 · 11:00 · Raúl Vega'); }} />
      <AppointmentModal open={appointment} close={() => setAppointment(false)} save={async (newAppointment) => { const saved = await createAppointment(db, newAppointment); setAppointments(old => [...old, saved]); setLocalChanges(await queueCount(db)); setAppointment(false); }} />
      <CameraCapture visible={cameraKind !== null} kind={cameraKind ?? 'before'} onClose={() => setCameraKind(null)} onCaptured={async uri => { await saveAttachment(db, cameraKind ?? 'before', uri); setLocalChanges(await queueCount(db)); }} />
    </SafeAreaView>
  );
}

function Today({ onBegin, completed }: { onBegin: (v: Visit) => void; completed: boolean }) {
  return <ScrollView contentContainerStyle={s.content}><Text style={s.date}>MIÉRCOLES, 29 DE JULIO</Text><Text style={s.lead}>Tu ruta de hoy</Text>{completed && <View style={s.success}><Text style={s.successTitle}>✓ Orden cerrada localmente</Text><Text style={s.successText}>La nota de Martha quedó lista. La información permanecerá en el teléfono; no se envió a ningún servidor.</Text></View>}{visits.map(v => <View style={[s.card, v.overdue && s.overdue]} key={v.name}><View style={s.row}><Text style={s.time}>{v.time}</Text><Text style={[s.badge, v.overdue && s.warn, completed && v.name.includes('Martha') && s.done]}>{completed && v.name.includes('Martha') ? 'TERMINADA' : v.overdue ? 'SIN CERRAR' : 'PENDIENTE'}</Text></View><Text style={s.name}>{v.name}</Text><Text style={s.detail}>{v.service} · {v.zone}</Text><View style={s.actions}>{['📍 Ir', '📞 Llamar', '💬 WhatsApp'].map(a => <Pressable key={a} style={s.action} onPress={() => Alert.alert(a.slice(3), `Abrir ${a.slice(3).toLowerCase()} para ${v.name}`)}><Text style={s.actionText}>{a}</Text></Pressable>)}</View>{!v.overdue && !(completed && v.name.includes('Martha')) && <Pressable style={s.primary} onPress={() => onBegin(v)}><Text style={s.primaryText}>▶  Iniciar visita</Text></Pressable>}</View>)}</ScrollView>;
}

function Agenda({ onAdd, appointments }: { onAdd: () => void; appointments: Appointment[] }) {
  const schedule = [['10:00', 'Sra. Martha', 'Fumigación general'], ['12:00', '', ''], ['13:00', 'Taquería El Güero', 'Control mensual'], ['16:00', '', ''], ...appointments.map(a => [a.time, a.name, a.service])];
  return <ScrollView contentContainerStyle={s.content}><View style={s.days}>{['L 27', 'M 28', 'M 29', 'J 30', 'V 31'].map((d, i) => <View key={d} style={[s.day, i === 2 && s.dayOn]}><Text style={i === 2 ? s.dayTextOn : s.dayText}>{d}</Text></View>)}</View><Text style={s.sectionTitle}>Miércoles 29</Text>{schedule.map(([time, name, service], index) => <View style={s.slot} key={`${time}-${index}`}><Text style={s.slotTime}>{time}</Text><Pressable style={name ? s.event : s.free} onPress={!name ? onAdd : undefined}><Text style={name ? s.eventName : s.freeText}>{name || '+ Toca para agendar'}</Text>{service ? <Text style={s.eventDetail}>{service}</Text> : null}</Pressable></View>)}</ScrollView>;
}

function Order({ lines, setLines, total, payment, setPayment, followup, setFollowup, onClose, onPhoto }: { lines: Line[]; setLines: React.Dispatch<React.SetStateAction<Line[]>>; total: number; payment: string; setPayment: (p: string) => void; followup: string; setFollowup: (p: string) => void; onClose: () => Promise<void>; onPhoto: (kind: 'before' | 'after') => void }) {
  const update = (id: number, value: string) => setLines(old => old.map(l => l.id === id ? { ...l, price: Number(value.replace(/[^0-9.]/g, '')) || 0 } : l));
  return <ScrollView contentContainerStyle={s.content}><Text style={s.inProgress}>● VISITA EN CURSO · SRA. MARTHA</Text><View style={s.photos}><Pressable style={s.photo} onPress={() => onPhoto('before')}><Text style={s.photoIcon}>📷</Text><Text style={s.photoText}>Foto antes</Text></Pressable><Pressable style={s.photo} onPress={() => onPhoto('after')}><Text style={s.photoIcon}>📷</Text><Text style={s.photoText}>Foto después</Text></Pressable></View><View style={s.dictation}><Text style={s.dictationLabel}>🎙 DICTADO INTERPRETADO</Text><Text style={s.quote}>“Fumigué toda la casa, apliqué gel en cocina, cobré novecientos cincuenta.”</Text><Text style={s.preview}>Revisa los renglones antes de confirmar</Text></View><View style={s.card}>{lines.map(line => <View style={s.lineItem} key={line.id}><View style={{ flex: 1 }}><Text style={s.lineName}>{line.concept}</Text><Text style={s.detail}>1 × precio unitario</Text></View><TextInput accessibilityLabel={`Precio de ${line.concept}`} keyboardType="decimal-pad" value={String(line.price)} onChangeText={v => update(line.id, v)} style={s.price} /></View>)}<Pressable onPress={() => setLines(old => [...old, { id: Date.now(), concept: 'Nuevo servicio', price: 0 }])}><Text style={s.add}>＋ Agregar renglón</Text></Pressable><View style={s.total}><Text style={s.totalText}>Total</Text><Text style={s.totalText}>${total.toFixed(2)}</Text></View></View><Picker label="Cobro" options={['Efectivo', 'Transferencia', 'Pendiente']} value={payment} setValue={setPayment} /><Picker label="Seguimiento" options={['1 mes', '3 meses', '6 meses']} value={followup} setValue={setFollowup} /><Pressable style={s.primary} onPress={() => Alert.alert('Confirma el cierre', `Total $${total.toFixed(2)} · ${payment}. Se guardará en SQLite y entrará a la cola offline.`, [{ text: 'Seguir editando', style: 'cancel' }, { text: 'Cerrar localmente', onPress: onClose }])}><Text style={s.primaryText}>✓  Cerrar orden localmente</Text></Pressable></ScrollView>;
}

function Picker({ label, options, value, setValue }: { label: string; options: string[]; value: string; setValue: (v: string) => void }) { return <View><Text style={s.label}>{label}</Text><ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.picks}>{options.map(o => <Pressable key={o} onPress={() => setValue(o)} style={[s.pick, value === o && s.pickOn]}><Text style={[s.pickText, value === o && s.pickTextOn]}>{o}</Text></Pressable>)}</ScrollView></View>; }

function Clients({ query, setQuery }: { query: string; setQuery: (q: string) => void }) {
  const shown = clients.filter(c => c.join(' ').toLowerCase().includes(query.toLowerCase()));
  return <ScrollView contentContainerStyle={s.content}><TextInput value={query} onChangeText={setQuery} placeholder="Buscar nombre, teléfono o colonia…" placeholderTextColor={C.muted} style={s.search} />{shown.map(([name, detail, amount]) => <Pressable key={name} style={s.client}><View style={{ flex: 1 }}><Text style={s.name}>{name}</Text><Text style={[s.detail, detail.includes('saldo') && { color: C.clay }]}>{detail}</Text></View><Text style={s.clientAmount}>{amount}</Text></Pressable>)}<View style={s.tip}><Text style={s.tipText}><Text style={{ fontWeight: '800' }}>3 clientes</Text> ya cumplen 6 meses sin servicio. Toca para agendar seguimiento.</Text></View></ScrollView>;
}

function VoiceModal({ open, close, confirm }: { open: boolean; close: () => void; confirm: () => void }) { return <Modal visible={open} transparent animationType="slide" onRequestClose={close}><Pressable style={s.backdrop} onPress={close}><Pressable style={s.sheet} onPress={() => {}}><View style={s.handle} /><Text style={s.sheetIcon}>🎙</Text><Text style={s.sheetTitle}>Te escucho</Text><Text style={s.quoteDark}>“Agéndame al señor Raúl el jueves a las once, mantenimiento de minisplit.”</Text><View style={s.previewCard}><Text style={s.label}>PREVIEW · NADA SE GUARDA TODAVÍA</Text><Text style={s.name}>Raúl Vega</Text><Text style={s.detail}>Jueves 30 · 11:00 · Mantenimiento de minisplit</Text></View><Pressable style={s.primary} onPress={confirm}><Text style={s.primaryText}>Confirmar cita</Text></Pressable><Pressable onPress={close}><Text style={s.cancel}>Cancelar</Text></Pressable></Pressable></Pressable></Modal>; }

function AppointmentModal({ open, close, save }: { open: boolean; close: () => void; save: (appointment: Omit<Appointment, 'id'>) => Promise<void> }) { const [name, setName] = useState(''); const [service, setService] = useState(''); return <Modal visible={open} transparent animationType="slide" onRequestClose={close}><View style={s.backdrop}><View style={s.sheet}><View style={s.handle} /><Text style={s.sheetTitle}>Nueva cita</Text><Text style={s.label}>CLIENTE</Text><TextInput value={name} onChangeText={setName} placeholder="Nombre del cliente" style={s.search} /><Text style={s.label}>FECHA Y HORA</Text><View style={s.search}><Text>29 jul 2026 · 12:00</Text></View><Text style={s.label}>SERVICIO</Text><TextInput value={service} onChangeText={setService} placeholder="¿Qué trabajo harás?" style={s.search} /><Pressable style={s.primary} onPress={() => { if (!name.trim()) return Alert.alert('Falta el cliente', 'Escribe al menos su nombre.'); void save({ time: '12:00', name: name.trim(), service: service.trim() || 'Servicio por definir' }); setName(''); setService(''); }}><Text style={s.primaryText}>Guardar cita local</Text></Pressable><Pressable onPress={close}><Text style={s.cancel}>Cancelar</Text></Pressable></View></View></Modal>; }

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: C.paper }, header: { paddingHorizontal: 20, paddingTop: 14, paddingBottom: 12, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }, eyebrow: { fontSize: 10, color: C.muted, fontWeight: '800', letterSpacing: 1.2 }, title: { fontSize: 30, fontWeight: '800', color: C.ink }, sync: { backgroundColor: C.soft, borderRadius: 20, paddingHorizontal: 10, paddingVertical: 7 }, syncText: { color: C.dark, fontSize: 11, fontWeight: '700' }, syncPending: { backgroundColor: '#FBEFDB' }, syncPendingText: { color: '#8A5A12' }, content: { padding: 16, paddingBottom: 120, gap: 12 }, date: { color: C.muted, fontSize: 11, letterSpacing: 1.2, fontWeight: '800' }, lead: { fontSize: 20, fontWeight: '700', marginBottom: 2 }, success: { backgroundColor: C.soft, borderRadius: 14, padding: 14, borderLeftWidth: 4, borderLeftColor: C.petrol }, successTitle: { color: C.dark, fontWeight: '800' }, successText: { color: C.dark, fontSize: 12, lineHeight: 18, marginTop: 4 }, card: { backgroundColor: C.white, borderWidth: 1, borderColor: C.line, borderRadius: 18, padding: 15 }, overdue: { borderLeftWidth: 4, borderLeftColor: C.amber }, row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }, time: { fontSize: 19, fontWeight: '800', color: C.dark }, badge: { fontSize: 9, fontWeight: '800', backgroundColor: C.soft, color: C.dark, borderRadius: 20, paddingHorizontal: 9, paddingVertical: 5 }, warn: { backgroundColor: '#FBEFDB', color: '#8A5A12' }, done: { backgroundColor: C.soft, color: C.dark }, name: { fontWeight: '700', fontSize: 16, marginTop: 5, color: C.ink }, detail: { color: C.muted, fontSize: 12, marginTop: 3 }, actions: { flexDirection: 'row', gap: 7, marginTop: 13 }, action: { flex: 1, alignItems: 'center', borderWidth: 1, borderColor: C.line, paddingVertical: 9, borderRadius: 10 }, actionText: { fontSize: 11, fontWeight: '600' }, primary: { backgroundColor: C.petrol, borderRadius: 13, padding: 14, alignItems: 'center', marginTop: 12 }, primaryText: { color: C.white, fontWeight: '800', fontSize: 14 }, fab: { position: 'absolute', right: 18, bottom: 88, width: 62, height: 62, borderRadius: 31, backgroundColor: C.amber, borderWidth: 3, borderColor: C.white, alignItems: 'center', justifyContent: 'center', elevation: 8 }, fabIcon: { fontSize: 27 }, nav: { height: 72, flexDirection: 'row', borderTopWidth: 1, borderTopColor: C.line, backgroundColor: C.white, paddingBottom: 6 }, navItem: { flex: 1, alignItems: 'center', justifyContent: 'center' }, navIcon: { color: C.muted, fontSize: 19 }, navText: { color: C.muted, fontSize: 10, marginTop: 2 }, navOn: { color: C.petrol, fontWeight: '800' }, days: { flexDirection: 'row', gap: 6 }, day: { flex: 1, paddingVertical: 13, borderRadius: 12, backgroundColor: C.white, alignItems: 'center', borderWidth: 1, borderColor: C.line }, dayOn: { backgroundColor: C.petrol, borderColor: C.petrol }, dayText: { color: C.muted, fontWeight: '700' }, dayTextOn: { color: C.white, fontWeight: '800' }, sectionTitle: { fontSize: 18, fontWeight: '800', marginVertical: 8 }, slot: { flexDirection: 'row', minHeight: 66, gap: 10 }, slotTime: { width: 45, color: C.muted, fontSize: 11, paddingTop: 12 }, event: { flex: 1, padding: 11, borderRadius: 12, backgroundColor: C.soft, borderLeftWidth: 4, borderLeftColor: C.petrol }, eventName: { color: C.dark, fontWeight: '800' }, eventDetail: { color: C.dark, fontSize: 12, marginTop: 3 }, free: { flex: 1, borderWidth: 1, borderStyle: 'dashed', borderColor: C.line, borderRadius: 12, alignItems: 'center', justifyContent: 'center' }, freeText: { color: C.muted, fontSize: 12 }, inProgress: { color: C.petrol, fontSize: 11, fontWeight: '800', letterSpacing: .6 }, photos: { flexDirection: 'row', gap: 10 }, photo: { flex: 1, height: 78, backgroundColor: C.white, borderWidth: 1, borderStyle: 'dashed', borderColor: '#BFC9C2', borderRadius: 14, alignItems: 'center', justifyContent: 'center' }, photoIcon: { fontSize: 22 }, photoText: { color: C.muted, fontSize: 11, marginTop: 3 }, dictation: { backgroundColor: '#10322A', borderRadius: 16, padding: 15 }, dictationLabel: { color: C.amber, fontSize: 10, fontWeight: '800', letterSpacing: 1 }, quote: { color: '#C8DED5', fontStyle: 'italic', lineHeight: 20, marginTop: 7 }, preview: { color: C.white, fontSize: 11, fontWeight: '700', marginTop: 9 }, lineItem: { flexDirection: 'row', alignItems: 'center', borderBottomWidth: 1, borderBottomColor: C.line, paddingVertical: 10 }, lineName: { fontSize: 13, fontWeight: '700' }, price: { width: 78, borderWidth: 1, borderColor: C.line, borderRadius: 9, padding: 8, textAlign: 'right', fontWeight: '700' }, add: { color: C.petrol, fontWeight: '700', paddingVertical: 12 }, total: { flexDirection: 'row', justifyContent: 'space-between', paddingTop: 10 }, totalText: { fontSize: 19, fontWeight: '800' }, label: { color: C.muted, fontSize: 10, fontWeight: '800', letterSpacing: 1, marginTop: 6, marginBottom: 6 }, picks: { gap: 7 }, pick: { borderWidth: 1, borderColor: C.line, backgroundColor: C.white, borderRadius: 10, paddingVertical: 9, paddingHorizontal: 13 }, pickOn: { borderColor: C.petrol, backgroundColor: C.soft }, pickText: { color: C.muted, fontSize: 12 }, pickTextOn: { color: C.dark, fontWeight: '800' }, search: { backgroundColor: C.white, borderWidth: 1, borderColor: C.line, borderRadius: 13, padding: 13, color: C.ink }, client: { backgroundColor: C.white, borderWidth: 1, borderColor: C.line, borderRadius: 15, padding: 14, flexDirection: 'row', alignItems: 'center' }, clientAmount: { color: C.dark, fontSize: 12, fontWeight: '800', maxWidth: 100, textAlign: 'right' }, tip: { marginTop: 8, borderRadius: 14, padding: 15, backgroundColor: C.soft, borderWidth: 1, borderColor: C.petrol }, tipText: { color: C.dark, lineHeight: 20 }, backdrop: { flex: 1, backgroundColor: 'rgba(10,30,22,.45)', justifyContent: 'flex-end' }, sheet: { backgroundColor: C.paper, borderTopLeftRadius: 28, borderTopRightRadius: 28, padding: 22, paddingBottom: 34 }, handle: { width: 44, height: 4, borderRadius: 2, backgroundColor: '#C8C5BC', alignSelf: 'center', marginBottom: 18 }, sheetIcon: { textAlign: 'center', fontSize: 38 }, sheetTitle: { fontSize: 25, fontWeight: '800', textAlign: 'center', marginBottom: 12 }, quoteDark: { color: C.ink, textAlign: 'center', fontStyle: 'italic', lineHeight: 21, paddingHorizontal: 12 }, previewCard: { backgroundColor: C.white, borderWidth: 1, borderColor: C.line, borderRadius: 15, padding: 14, marginTop: 18 }, cancel: { color: C.muted, textAlign: 'center', padding: 14, fontWeight: '700' }, sectionTitle2: { fontWeight: '800' },
});
