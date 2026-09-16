export default {
  slug: 'book',
  announcement: 'Same-week appointments are available in General practice until Thursday.',
  title: 'Book an appointment',
  intro:
    'Use the form below to request a slot. Our desk confirms bookings by ' +
    'phone within one business day.',
  site: {
    name: 'Lanternwell Clinic',
    nav: [
      { label: 'Home', href: '#home' },
      { label: 'Services', href: '#services' },
      { label: 'Book an appointment', href: '#book' },
      { label: 'Contact', href: '#contact' },
    ],
  },
  cta: { label: 'Check the phone line', href: 'tel:+1-555-0100' },
  cards: [
    {
      title: 'First visit',
      text: 'Please arrive 15 minutes early so we can complete the intake form.',
      image: { src: '/img/first-visit.svg', alt: 'The clinic waiting room with chairs and a reception window' },
      state: 'open',
      stateLabel: 'Open – slots open',
    },
  ],
  sidebarLinks: [
    { label: 'Emergency line', href: 'tel:+1-555-0100' },
    { label: 'Cancel a booking', href: '#cancel' },
  ],
  form: {
    title: 'Appointment request',
    submitLabel: 'Request slot',
    note: 'We keep one walk-in slot per morning for urgent needs.',
    fields: [
      { type: 'text', name: 'full-name', label: 'Full name', hint: 'Jane Doe' },
      { type: 'text', name: 'phone', label: 'Phone number', hint: '(555) 010-1234', inputType: 'tel' },
      { type: 'select', name: 'service', label: 'Service needed', placeholderOption: 'Choose a service',
        options: [
          { value: 'gp', label: 'General practice' },
          { value: 'imaging', label: 'Imaging' },
          { value: 'lab', label: 'Laboratory' },
          { value: 'physio', label: 'Physiotherapy' },
        ] },
      { type: 'textarea', name: 'notes', label: 'Anything we should know', hint: 'Symptoms, mobility needs, preferred times' },
    ],
  },
};