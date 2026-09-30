/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Escanor's dark theme, taken from the website's landing scope: an off-black page, warm off-white ink and
        // a single gold signal. Names are unchanged so every screen picks it up together.
        primary: {
          DEFAULT: '#f2a73b',
          active: '#e39a2c',
          disabled: '#3e3c37',
        },
        ink: '#f3f1ec',
        body: {
          DEFAULT: '#beb2b1',
          strong: '#e2dfd8',
        },
        muted: {
          DEFAULT: '#98948b',
          soft: '#7e7b73',
        },
        hairline: {
          DEFAULT: '#242320',
          soft: '#181816',
        },
        canvas: '#050505',
        surface: {
          soft: '#090908',
          card: '#151513',
          'cream-strong': '#1f1e1b',
          dark: '#080807',
          'dark-elevated': '#151513',
          'dark-soft': '#0c0c0b',
        },
        'on-primary': '#180e02',
        'on-dark': {
          DEFAULT: '#f3f1ec',
          soft: '#98948b',
        },
        permission: '#8b93ff',
        'accent-teal': '#5db8a6',
        'accent-amber': '#e8a55a',
        success: '#5db872',
        warning: '#e0b040',
        error: '#ef6b62',
      },
      fontFamily: {
        // One family throughout, as on the website.
        display: ['Gellix', 'Inter', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'],
        sans: ['Gellix', 'Inter', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      borderRadius: {
        xs: '4px',
        sm: '6px',
        md: '8px',
        lg: '12px',
        xl: '16px',
        pill: '9999px',
      },
      boxShadow: {
        panel: '0 1px 3px rgba(0, 0, 0, 0.5)',
        elevated: '0 8px 24px -8px rgba(0, 0, 0, 0.6)',
      },
      keyframes: {
        blink: {
          '0%, 49%': { opacity: 1 },
          '50%, 100%': { opacity: 0 },
        },
        pulseDot: {
          '0%, 100%': { opacity: 0.3 },
          '50%': { opacity: 1 },
        },
      },
      animation: {
        pulseDot: 'pulseDot 1.2s ease-in-out infinite',
        blink: 'blink 1s steps(1) infinite',
      },
    },
  },
  plugins: [],
};
