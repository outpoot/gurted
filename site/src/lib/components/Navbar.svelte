/<script lang="ts">
  import { Button } from '$lib/components/ui/button';
  import { Download, FileText, Info } from 'lucide-svelte';
</script>

<nav class="fixed top-4 left-1/2 backdrop-blur-none  transform -translate-x-1/2 z-50 w-full max-w-2xl">
    <div class="bg-background/65 backdrop-blur-xl border border-border/50 rounded-3xl px-6 py-3 shadow-2xl">
    <div class="flex items-center justify-between">
      <!-- Logo and Brand -->
      <a href="/" class="flex items-center space-x-3">
        <div class="w-8 h-8 flex items-center justify-center">
          <img src="/favicon.svg" alt="Gurted Logo" class="w-8 h-8" />
        </div>
        <span class="font-gurted font-bold text-xl text-gurted-gradient">Gurted</span>
      </a>

      <!-- Navigation Links -->
      <div class="hidden md:flex items-center space-x-1">
        <Button variant="ghost" size="sm" class="text-muted-foreground hover:text-foreground" href="https://docs.gurted.com">
          Docs
        </Button>
        <Button variant="ghost" size="sm" class="text-muted-foreground hover:text-foreground" href="https://github.com/outpoot/gurted">
          GitHub
        </Button>
        <a href="/download">
          <Button size="sm" class="bg-primary hover:bg-primary/90 text-primary-foreground shadow-lg" href="/download">
            Download
          </Button>
        </a>
      </div>

      <!-- Mobile Menu Button -->
      <div class="md:hidden">
        <a href="/download">
          <Button size="sm" class="bg-primary hover:bg-primary/90 text-primary-foreground">
            <Download class="w-4 h-4" />
          </Button>
        </a>
      </div>
    </div>
  </div>
</nav>

<style>
  nav {
    backdrop-filter: blur(20px);
    -webkit-backdrop-filter: blur(20px);
  }
</style>
