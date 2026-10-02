declare const __APP_VERSION__: string | undefined;

/** The version this build was made from (stamped in at build time). */
export const APP_VERSION: string = typeof __APP_VERSION__ === 'string' ? __APP_VERSION__ : 'dev';
