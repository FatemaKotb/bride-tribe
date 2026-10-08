// The app's look: lavender, soft and rounded. Everything goes through
// Mantine's theme, not custom CSS.
import { createTheme, type CSSVariablesResolver, type MantineColorsTuple } from '@mantine/core';

// Light shades for backgrounds and tints. Shade 6, used behind white text
// on buttons, is deep enough to read (5:1).
const lavender: MantineColorsTuple = [
  '#f8f4fd',
  '#efe7fa',
  '#dfd0f4',
  '#cbb6ec',
  '#b69be2',
  '#9f81d6',
  '#7c5dbd',
  '#6a4ea6',
  '#58418b',
  '#46346f',
];

// One font everywhere, headings included. Nunito loads from Google Fonts
// in index.html.
const FONT = 'Nunito, "Segoe UI", Roboto, sans-serif';

export const theme = createTheme({
  primaryColor: 'lavender',
  primaryShade: 6,
  colors: { lavender },
  fontFamily: FONT,
  headings: {
    fontFamily: FONT,
    fontWeight: '800',
  },
  defaultRadius: 'lg',
  components: {
    Button: { defaultProps: { radius: 'xl' } },
    Badge: { defaultProps: { radius: 'xl' } },
    Card: { defaultProps: { radius: 'lg', shadow: 'xs' } },
    Paper: { defaultProps: { radius: 'lg' } },
    Title: { defaultProps: { c: 'lavender.9' } },
    Drawer: { defaultProps: { radius: 'lg' } },
    Modal: { defaultProps: { radius: 'lg' } },
    Notification: { defaultProps: { radius: 'lg' } },
  },
});

// A faint lavender page, lavender borders, and a lavender-grey for
// secondary text that stays readable on the tinted page.
export const cssVariablesResolver: CSSVariablesResolver = () => ({
  variables: {},
  light: {
    '--mantine-color-body': '#faf7fe',
    '--mantine-color-default-border': lavender[3],
    '--mantine-color-dimmed': '#726a80',
  },
  dark: {},
});
