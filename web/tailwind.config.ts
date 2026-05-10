import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        bg: "#FAFAF8",
        surface: "#F2F0EC",
        border: "#E8E4DF",
        text: "#1A1A18",
        muted: "#6B6862",
        accent: "#8B7355",
        "accent-light": "#C4A882",
      },
      fontFamily: {
        serif: ["Georgia", "Cambria", "serif"],
        sans: ["system-ui", "-apple-system", "sans-serif"],
      },
      lineHeight: {
        relaxed: "1.7",
        loose: "1.9",
      },
    },
  },
  plugins: [],
};

export default config;
