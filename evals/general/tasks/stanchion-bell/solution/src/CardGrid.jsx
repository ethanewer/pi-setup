import StatusDot from './StatusDot.jsx';

/**
 * Grid of service cards.
 */
export default function CardGrid({ cards }) {
  return (
    <section className="card-grid" aria-label="Services">
      <h2 className="section-title">Our services</h2>
      {cards.map((card) => (
        <article key={card.title} className="service-card">
          <img className="card-image" src={card.image.src} alt={card.image.alt} />
          <h3 className="card-title">{card.title}</h3>
          <p className="card-text">{card.text}</p>
          <StatusDot state={card.state} stateLabel={card.stateLabel} />
        </article>
      ))}
    </section>
  );
}
