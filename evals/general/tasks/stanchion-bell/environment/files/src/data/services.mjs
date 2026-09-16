export default {
  slug: 'services',
  announcement: 'Flu vaccinations available every afternoon without an appointment.',
  title: 'Services and fees',
  intro:
    'Every service below can be booked online or by phone. Fees shown are ' +
    'per visit; most insurance plans are accepted at the desk.',
  site: {
    name: 'Lanternwell Clinic',
    nav: [
      { label: 'Home', href: '#home' },
      { label: 'Services', href: '#services' },
      { label: 'Book an appointment', href: '#book' },
      { label: 'Contact', href: '#contact' },
    ],
  },
  cta: { label: 'Book an appointment', href: '#book' },
  cards: [
    {
      title: 'Imaging',
      text: 'X-ray and ultrasound with same-day reporting for referrals.',
      image: { src: '/img/imaging.svg', alt: 'An ultrasound machine in a dim imaging suite' },
      state: 'open',
      stateLabel: 'Open for referrals',
    },
    {
      title: 'Laboratory',
      text: 'Blood and urine testing. Results online within 48 hours.',
      image: { src: '/img/laboratory.svg', alt: 'A lab technician loading samples into a centrifuge' },
      state: 'busy',
      stateLabel: 'Busy – results may take 72 hours this week',
    },
    {
      title: 'Physiotherapy',
      text: 'Injury assessment and rehabilitation plans.',
      image: { src: '/img/physio.svg', alt: 'A physiotherapist guiding a patient through an exercise' },
      state: 'open',
      stateLabel: 'Open – new slots released Friday',
    },
  ],
  sidebarLinks: [
    { label: 'Price list (PDF)', href: '/fees.pdf' },
    { label: 'Insurance partners', href: '#insurance' },
    { label: 'Lab requisition form', href: '#requisition' },
  ],
  form: null,
};