export default {
  slug: 'contact',
  announcement: 'The clinic moves to temporary reception until 10 March while the front desk is remodelled.',
  title: 'Contact and location',
  intro:
    'Find us on the corner of Heugh Lane and Market Street. Buses 4 and 12 ' +
    'stop outside; paid parking is one block north.',
  site: {
    name: 'Lanternwell Clinic',
    nav: [
      { label: 'Home', href: '#home' },
      { label: 'Services', href: '#services' },
      { label: 'Book an appointment', href: '#book' },
      { label: 'Contact', href: '#contact' },
    ],
  },
  cta: { label: 'Get directions', href: '#directions' },
  cards: [
    {
      title: 'Main reception',
      text: 'Open 08:00–18:00 weekdays and 09:00–13:00 Saturdays.',
      image: { src: '/img/reception.svg', alt: 'The clinic reception desk with staff at the counter' },
      state: 'open',
      stateLabel: 'Open',
    },
    {
      title: 'After-hours advice',
      text: 'Call the emergency line for a nurse callback any evening.',
      image: { src: '/img/advice.svg', alt: 'A nurse on the phone at a quiet desk' },
      state: 'busy',
      stateLabel: 'Busy – calls on hold tonight',
    },
    {
      title: 'Pharmacy window',
      text: 'Collections from the window on the Heugh Lane side.',
      image: { src: '/img/pharmacy.svg', alt: 'The pharmacy window with a sign saying collection point' },
      state: 'closed',
      stateLabel: 'Closed after 18:00',
    },
  ],
  sidebarLinks: [
    { label: 'Email us', href: 'mailto:hello@lanternwell.example' },
    { label: 'After-hours phone', href: 'tel:+1-555-0164' },
    { label: 'Accessibility parking', href: '#parking' },
  ],
  form: null,
};