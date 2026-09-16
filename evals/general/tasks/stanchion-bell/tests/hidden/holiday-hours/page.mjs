export default {
  slug: 'holiday-hours',
  announcement: 'Holiday hours: 24 and 31 December we close at 13:00.',
  title: 'December hours and closures',
  intro:
    'During the December holidays the clinic keeps a reduced rota. ' +
    'Prescriptions can be picked up through the pharmacy window all week.',
  cta: { label: 'Holiday rota PDF', href: '/rota.pdf' },
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
      title: 'Pharmacy window',
      text: 'Open every weekday 09:00–13:00 throughout the holidays.',
      image: { src: '/img/pharmacy.svg', alt: 'The pharmacy window with a sign saying "collection point"' },
      state: 'open',
      stateLabel: 'Open for collections',
    },
    {
      title: 'Walk-in urgent care',
      text: 'Limited slots each morning; call ahead to hold one.',
      image: { src: '/img/urgent.svg', alt: 'A clinician at the urgent care desk' },
      state: 'busy',
      stateLabel: 'Busy – slots nearly full',
    },
  ],
  sidebarLinks: [
    { label: 'Emergency line', href: 'tel:+1-555-0100' },
    { label: 'Holiday pharmacy rota', href: '#rota' },
  ],
  form: null,
};