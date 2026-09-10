export default {
  slug: 'home',
  announcement: 'We are now accepting new patients for 2026.',
  title: 'Compassionate care for your whole family',
  intro:
    'Lanternwell Community Clinic provides general practice, diagnostics and ' +
    'physiotherapy under one roof, with same-week appointments for urgent needs.',
  cta: { label: 'Book an appointment', href: '#book' },
  site: {
    name: 'Lanternwell Clinic',
    nav: [
      { label: 'Home', href: '#home' },
      { label: 'Services', href: '#services' },
      { label: 'Book an appointment', href: '#book' },
      { label: 'Contact', href: '#contact' },
    ],
  },
  cards: [
    {
      title: 'General practice',
      text: 'Same-week appointments with our family physicians, Monday to Friday.',
      image: { src: '/img/general-practice.svg', alt: 'A doctor listening to a patient during a consultation' },
      state: 'open',
      stateLabel: 'Open now',
    },
    {
      title: 'Routine check-ups',
      text: 'Blood-pressure and wellness checks with our nursing team.',
      image: { src: '/img/checkup.svg', alt: 'A nurse taking a patient’s blood pressure reading' },
      state: 'busy',
      stateLabel: 'Busy – walk-ins wait up to 30 minutes',
    },
    {
      title: 'Saturday clinic',
      text: 'Urgent care and vaccinations every Saturday, 09:00–13:00.',
      image: { src: '/img/saturday.svg', alt: 'The clinic reception desk on a quiet morning' },
      state: 'closed',
      stateLabel: 'Closed today, reopens Saturday',
    },
  ],
  sidebarLinks: [
    { label: 'Emergency line', href: 'tel:+1-555-0100' },
    { label: 'Test results portal', href: '#results' },
    { label: 'Pay a bill', href: '#pay' },
  ],
  form: null,
};
