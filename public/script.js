const currentPage = document.body.dataset.page;
const navLinks = Array.from(document.querySelectorAll("[data-nav]"));

navLinks.forEach((link) => {
  if (link.dataset.nav === currentPage) {
    link.setAttribute("aria-current", "page");
  }
});