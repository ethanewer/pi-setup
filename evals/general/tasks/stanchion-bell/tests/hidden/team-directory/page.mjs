export default {
  slug: 'our-team',
  announcement: 'Two of our physicians are away the week of 23 March.',
  title: 'Meet the care team',
  intro:
    'Our physicians, nurses and allied staff work together so every visit ' +
    'starts with a warm welcome and ends with a clear next step.',
  cta: { label: 'Read the team handbook', href: '#handbook' },
  site: {
    name: 'Lanternwell Clinic',
    nav: [
      { label: 'Home', href: '#home' },
      { label: 'Our team', href: '#team' },
      { label: 'Book an appointment', href: '#book' },
      { label: 'Contact', href: '#contact' },
    ],
  },
  cards: [
    {
      title: 'Dr. Amara Okafor',
      text: 'Family medicine lead. Accepts new patients from the clinic list.',
      image: { src: '/img/amara.svg', alt: 'Portrait of Dr. Okafor in a white coat' },
      state: 'open',
      stateLabel: 'Open – accepting new patients',
    },
    {
      title: 'Nurse Daniel Reyes',
      text: 'Runs the diabetes clinic and home-visit programme.',
      image: { src: '/img/daniel.svg', alt: 'Portrait of nurse Reyes holding a clipboard' },
      state: 'busy',
      stateLabel: 'Busy – bookable from Friday',
    },
    {
      title: 'Dr. Priya Nair',
      text: 'Paediatrician. On leave from 23 March to 4 April.',
      image: { src: '/img/priya.svg', alt: 'Portrait of Dr. Nair in a pediatric exam room' },
      state: 'closed',
      stateLabel: 'Closed – on leave',
    },
  ],
  sidebarLinks: [
    { label: 'Email the team', href: 'mailto:care@lanternwell.example' },
    { label: 'Staff credentials', href: '#credentials' },
    { label: 'Campus map', href: '#map' },
  ],
  form: null,
};