/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Every colour is "R G B" in a CSS variable (palettes in styles.css), so themes switch without touching a screen and
        // opacity utilities such as bg-primary/15 keep working. Names are unchanged.
        primary: {
          DEFAULT: 'rgb(var(--c-primary) / <alpha-value>)',
          active: 'rgb(var(--c-primary-active) / <alpha-value>)',
          disabled: 'rgb(var(--c-primary-disabled) / <alpha-value>)',
        },
        ink: 'rgb(var(--c-ink) / <alpha-value>)',
        body: {
          DEFAULT: 'rgb(var(--c-body) / <alpha-value>)',
          strong: 'rgb(var(--c-body-strong) / <alpha-value>)',
        },
        muted: {
          DEFAULT: 'rgb(var(--c-muted) / <alpha-value>)',
          soft: 'rgb(var(--c-muted-soft) / <alpha-value>)',
        },
        hairline: {
          DEFAULT: 'rgb(var(--c-hairline) / <alpha-value>)',
          soft: 'rgb(var(--c-hairline-soft) / <alpha-value>)',
        },
        // Borders of controls (inputs, the composer, quiet buttons): one value, so every field looks the same.
        'line-strong': 'rgb(var(--c-line-strong) / <alpha-value>)',
        canvas: 'rgb(var(--c-canvas) / <alpha-value>)',
        surface: {
          soft: 'rgb(var(--c-surface-soft) / <alpha-value>)',
          card: 'rgb(var(--c-surface-card) / <alpha-value>)',
          'cream-strong': 'rgb(var(--c-surface-strong) / <alpha-value>)',
          // Code windows and tool output stay dark in every theme.
          dark: 'rgb(var(--c-code) / <alpha-value>)',
          'dark-elevated': 'rgb(var(--c-code-elevated) / <alpha-value>)',
          'dark-soft': 'rgb(var(--c-field) / <alpha-value>)',
        },
        'on-primary': 'rgb(var(--c-on-primary) / <alpha-value>)',
        'on-dark': {
          DEFAULT: 'rgb(var(--c-on-code) / <alpha-value>)',
          soft: 'rgb(var(--c-on-code-soft) / <alpha-value>)',
        },
        permission: 'rgb(var(--c-permission) / <alpha-value>)',
        'accent-teal': 'rgb(var(--c-teal) / <alpha-value>)',
        'accent-amber': 'rgb(var(--c-amber) / <alpha-value>)',
        success: 'rgb(var(--c-success) / <alpha-value>)',
        warning: 'rgb(var(--c-warning) / <alpha-value>)',
        error: 'rgb(var(--c-error) / <alpha-value>)',
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
