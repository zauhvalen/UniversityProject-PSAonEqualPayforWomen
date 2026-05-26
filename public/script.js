const currentPage = document.body.dataset.page;
const navLinks = Array.from(document.querySelectorAll("[data-nav]"));

navLinks.forEach((link) => {
  if (link.dataset.nav === currentPage) {
    link.setAttribute("aria-current", "page");
  }
});

// Fade-up animation using Intersection Observer
const observerOptions = {
  root: null,
  rootMargin: '0px',
  threshold: 0.1
};

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    }
  });
}, observerOptions);

const fadeElements = document.querySelectorAll('.fade-up');
fadeElements.forEach((el) => observer.observe(el));