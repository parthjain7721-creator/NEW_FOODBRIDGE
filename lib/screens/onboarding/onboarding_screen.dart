import 'package:flutter/material.dart';

import '../auth/login_screen.dart';
import '../../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  int _currentPage = 0;

  final List<OnboardingItem> _pages = const [
    OnboardingItem(
      icon: Icons.volunteer_activism_outlined,
      title: 'Rescue surplus food',
      description:
          'Share extra food with people and communities that need it before the rescue window closes.',
      color: AppTheme.forestGreen,
    ),
    OnboardingItem(
      icon: Icons.access_time_rounded,
      title: 'Track the rescue window',
      description:
          'FoodBridge records preparation time, storage details, and the remaining collection time.',
      color: AppTheme.navy,
    ),
    OnboardingItem(
      icon: Icons.connect_without_contact_rounded,
      title: 'Connect and deliver',
      description:
          'Donors, NGOs, and volunteers work together through a verified claim-and-collect process.',
      color: AppTheme.mediumGreen,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage == _pages.length - 1) {
      _openLogin();
      return;
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _skipOnboarding() {
    _openLogin();
  }

  void _openLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = _pages[_currentPage];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return _OnboardingPage(item: _pages[index]);
                },
              ),
            ),
            _buildBottomControls(currentItem),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppTheme.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(
                  'assets/images/foodbridge_logo.jpg',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'FoodBridge',
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: _skipOnboarding,
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(OnboardingItem currentItem) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _pages.length,
              (index) {
                final isActive = index == _currentPage;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? currentItem.color
                        : AppTheme.sageGreen.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 26),
          ElevatedButton(
            onPressed: _nextPage,
            child: Text(isLastPage ? 'Continue to Login' : 'Continue'),
          ),
          const SizedBox(height: 12),
          Text(
            '${_currentPage + 1} of ${_pages.length}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class OnboardingItem {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const OnboardingItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

class _OnboardingPage extends StatelessWidget {
  final OnboardingItem item;

  const _OnboardingPage({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 230,
            height: 230,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: item.color.withValues(alpha: 0.12),
                        blurRadius: 25,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    item.icon,
                    color: item.color,
                    size: 86,
                  ),
                ),
                Positioned(
                  top: 25,
                  right: 24,
                  child: _DecorationDot(color: item.color),
                ),
                Positioned(
                  bottom: 28,
                  left: 22,
                  child: _DecorationDot(
                    color: AppTheme.sageGreen,
                    size: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            item.description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.mutedText,
                  height: 1.55,
                ),
          ),
        ],
      ),
    );
  }
}

class _DecorationDot extends StatelessWidget {
  final Color color;
  final double size;

  const _DecorationDot({
    required this.color,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}