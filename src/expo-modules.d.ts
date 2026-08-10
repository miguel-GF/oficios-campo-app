declare module 'expo-print' {
  export function printToFileAsync(options: { html: string }): Promise<{ uri: string }>;
}
declare module 'expo-sharing' {
  export function isAvailableAsync(): Promise<boolean>;
  export function shareAsync(uri: string, options?: { mimeType?: string; dialogTitle?: string; UTI?: string }): Promise<void>;
}
declare module 'expo-file-system/legacy' {
  export const documentDirectory: string | null;
  export function makeDirectoryAsync(uri: string, options?: { intermediates?: boolean }): Promise<void>;
  export function copyAsync(options: { from: string; to: string }): Promise<void>;
  export const FileSystemUploadType: { BINARY_CONTENT: number };
  export function uploadAsync(url: string, fileUri: string, options: { httpMethod: string; uploadType: number; headers?: Record<string, string> }): Promise<{ status: number; body: string }>;
  export function writeAsStringAsync(uri: string, contents: string): Promise<void>;
}
declare module 'expo-secure-store' {
  export function setItemAsync(key: string, value: string): Promise<void>;
  export function getItemAsync(key: string): Promise<string | null>;
  export function deleteItemAsync(key: string): Promise<void>;
}
