import { Icon } from "./ui/Icon.jsx";

/**
 * PLACEHOLDER CONTENT.
 *
 * These are invented reviews standing in for real ones, at the product owner's
 * request. They are deliberately kept in one array with this comment on it so
 * they are easy to find and replace. Do not ship them to a public site as-is:
 * fabricated testimonials presented as genuine are a legal problem in most
 * markets, not just a content problem.
 */
const REVIEWS = [
  {
    quote:
      "My skin started to break out even after I used glycolic acid and retinol. The app explained to me that it was their combination causing my acne and now my face is finally clearing up.",
    name: "Priya R.",
    detail: "Sensitive · Acne",
  },
  {
    quote:
      "SkincareSync is the only service using an AM/PM split. The app told me why my blackheads did not disappear, because I was using vitamin C during the day and salicylic acid during the night every day.",
    name: "Marcus T.",
    detail: "Combination · Clogged pores",
  },
  {
    quote:
      "Every other tool just suggests products. With SkincareSync I was able to build a routine with the stuff I already had.",
    name: "Dani L.",
    detail: "Oily · Acne",
  },
];

export function Testimonials() {
  return (
    <section
      className="flex flex-col items-center gap-12 overflow-x-clip rounded-[40px] bg-linen px-6 py-16
                 md:gap-16 md:px-12 md:py-32"
      aria-labelledby="reviews-title"
    >
      <h2
        className="max-w-[24ch] text-center font-display text-section font-semibold tracking-tight text-forest text-balance"
        id="reviews-title"
      >
        What people found in <em className="italic">their own</em> routines
      </h2>

      <ul className="grid w-full max-w-7xl grid-cols-1 gap-8 md:grid-cols-3 md:gap-12">
        {REVIEWS.map((review, index) => (
          <li key={review.name} className={index % 2 === 1 ? "md:translate-y-12" : ""}>
            <div
              className="flex h-full flex-col gap-6 rounded-card border border-stone bg-white p-8
                         shadow-soft transition-[transform,box-shadow] duration-500 ease-organic
                         hover:-translate-y-2 hover:shadow-bloom"
            >
            <span className="font-display text-6xl leading-none text-clay" aria-hidden="true">
              &ldquo;
            </span>

            <p className="grow font-sans text-md leading-relaxed text-subtle">{review.quote}</p>

            <div className="flex items-center gap-4 border-t border-stone pt-6">
              <span
                className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-sage-100 text-forest"
                aria-hidden="true"
              >
                <Icon name="user" size={18} strokeWidth={1.5} />
              </span>
              <div>
                <p className="font-display text-lg font-semibold text-forest">{review.name}</p>
                <p className="font-sans text-2xs uppercase tracking-label text-muted">
                  {review.detail}
                </p>
              </div>
            </div>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
