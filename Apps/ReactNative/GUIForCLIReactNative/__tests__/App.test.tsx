import {apiBase} from '../src/api';
import {palette} from '../src/styles';

test('defaults to the local WebUI server base URL', () => {
  expect(apiBase()).toBe('http://127.0.0.1:8787');
});

test('exposes the light palette accent color', () => {
  expect(palette(false).accent).toBe('#2563eb');
});
