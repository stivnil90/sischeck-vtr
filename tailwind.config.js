/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./site/**/*.{html,js}'],
  theme: {
    extend: {
      colors: {
        tactical: {
          950: '#060a17',
          900: '#0b1329',
          800: '#141e3c',
          700: '#1e2d5a',
          gold: '#f59e0b',
          accent: '#3b82f6',
          danger: '#ef4444',
          success: '#10b981',
          warning: '#f59e0b'
        }
      }
    }
  },
  plugins: []
};
