import StatusDot from './StatusDot.jsx';

/**
 * Grid of service cards.
 */
export default function CardGrid({ cards }) {
  return (
    <section className="card-grid" aria-label="Services">
      <h4 className="section-title">Our services</h4>
      {cards.map((card) => (
        <article key={card.title} className="service-card">
          <img className="card-image" src={card.image.src} />
          <h4 className="card-title">{card.title}</h4>
          <p className="card-text">{card.text}</p>
          <StatusDot state={card.state} />
        </article>
      ))}
    </section>
  );
}
