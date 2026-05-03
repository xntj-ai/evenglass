// Tiny app-level state. Nanostores so we don't pull React just for two
// values. Persisted to localStorage on write; read once at boot.

import { atom, computed } from "nanostores";

import { DEVICE_ID_STORAGE_KEY, DEVICE_TOKEN_STORAGE_KEY } from "./constants";

export const $deviceId = atom<string | null>(localStorage.getItem(DEVICE_ID_STORAGE_KEY));
export const $deviceToken = atom<string | null>(localStorage.getItem(DEVICE_TOKEN_STORAGE_KEY));

export const $isEnrolled = computed([$deviceId, $deviceToken], (id, token) => Boolean(id && token));

$deviceId.subscribe((value) => {
  if (value) localStorage.setItem(DEVICE_ID_STORAGE_KEY, value);
  else localStorage.removeItem(DEVICE_ID_STORAGE_KEY);
});

$deviceToken.subscribe((value) => {
  if (value) localStorage.setItem(DEVICE_TOKEN_STORAGE_KEY, value);
  else localStorage.removeItem(DEVICE_TOKEN_STORAGE_KEY);
});

export function setEnrollment(deviceId: string, deviceToken: string): void {
  $deviceId.set(deviceId);
  $deviceToken.set(deviceToken);
}

export function clearEnrollment(): void {
  $deviceId.set(null);
  $deviceToken.set(null);
}
