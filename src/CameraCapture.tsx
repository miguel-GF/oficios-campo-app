import React, { useRef } from 'react';
import { Alert, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as FileSystem from 'expo-file-system/legacy';

type Props = { visible: boolean; kind: 'before' | 'after'; onClose: () => void; onCaptured: (uri: string) => Promise<void> };

export function CameraCapture({ visible, kind, onClose, onCaptured }: Props) {
  const camera = useRef<CameraView>(null);
  const [permission, requestPermission] = useCameraPermissions();

  const takePicture = async () => {
    const photo = await camera.current?.takePictureAsync({ quality: 0.7 });
    if (!photo?.uri) return;
    if (!FileSystem.documentDirectory) throw new Error('No se encontró almacenamiento permanente.');
    const directory = `${FileSystem.documentDirectory}evidence/`;
    await FileSystem.makeDirectoryAsync(directory, { intermediates: true });
    const permanentUri = `${directory}${Date.now()}.jpg`;
    await FileSystem.copyAsync({ from: photo.uri, to: permanentUri });
    await onCaptured(permanentUri);
    onClose();
  };

  if (!visible) return null;
  if (!permission?.granted) {
    return <Modal visible={visible} animationType="slide"><View style={s.permission}><Text style={s.title}>Jale necesita la cámara</Text><Text style={s.copy}>La foto se guarda primero en el teléfono y entra a la cola offline.</Text><Pressable style={s.button} onPress={async () => { const result = await requestPermission(); if (!result.granted) Alert.alert('Permiso no concedido', 'Puedes habilitarlo después desde Ajustes.'); }}><Text style={s.buttonText}>Permitir cámara</Text></Pressable><Pressable onPress={onClose}><Text style={s.cancel}>Cancelar</Text></Pressable></View></Modal>;
  }

  return <Modal visible={visible} animationType="slide"><View style={s.root}><CameraView ref={camera} style={s.camera} facing="back" /><View style={s.controls}><Pressable onPress={onClose}><Text style={s.controlText}>Cancelar</Text></Pressable><Pressable accessibilityLabel="Tomar fotografía" style={s.shutter} onPress={takePicture} /><Text style={s.controlText}>{kind === 'before' ? 'Antes' : 'Después'}</Text></View></View></Modal>;
}

const s = StyleSheet.create({ root: { flex: 1, backgroundColor: '#000' }, camera: { flex: 1 }, controls: { position: 'absolute', bottom: 0, left: 0, right: 0, padding: 30, paddingBottom: 48, backgroundColor: 'rgba(0,0,0,.45)', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }, shutter: { width: 72, height: 72, borderRadius: 36, backgroundColor: '#fff', borderWidth: 6, borderColor: '#E8A13D' }, controlText: { color: '#fff', fontWeight: '700', width: 70, textAlign: 'center' }, permission: { flex: 1, backgroundColor: '#F7F5F0', padding: 28, justifyContent: 'center' }, title: { color: '#1B2420', fontSize: 26, fontWeight: '800', textAlign: 'center' }, copy: { color: '#6B7570', lineHeight: 21, textAlign: 'center', marginVertical: 14 }, button: { backgroundColor: '#0E5E4A', padding: 15, borderRadius: 13, alignItems: 'center' }, buttonText: { color: '#fff', fontWeight: '800' }, cancel: { color: '#6B7570', textAlign: 'center', padding: 16, fontWeight: '700' } });
