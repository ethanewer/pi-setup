import CardGrid from './CardGrid.jsx';
import BookingForm from './BookingForm.jsx';

/**
 * The main content region: page title, intro, CTA, card grid and optional
 * form.
 */
export default function PageMain({ page }) {
  return (
    <main id="main-content" className="page-main">
      <h1 className="page-title">{page.title}</h1>
      <p className="intro">{page.intro}</p>
      <p className="page-cta">
        <a className="cta-link" href={page.cta.href}>{page.cta.label}</a>
      </p>
      {page.cards && page.cards.length ? <CardGrid cards={page.cards} /> : null}
      {page.form ? <BookingForm form={page.form} /> : null}
    </main>
  );
}
