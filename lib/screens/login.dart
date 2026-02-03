// lib/screens/login.dart
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsmart/providers/user_provider.dart';
import 'package:shiftsmart/screens/employee/empOnboard.dart';
import 'package:shiftsmart/screens/forgot_password.dart';
import 'package:shiftsmart/services/auth_service.dart';
import 'package:shiftsmart/services/notification_service.dart';
import 'package:shiftsmart/utils/fullscreen_helper.dart';
import 'package:shiftsmart/widgets/bottomnavbar.dart';
import 'package:shiftsmart/widgets/emp_bottomnavbar.dart';
import 'package:shiftsmart/widgets/loginBackground.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final AuthService _authService = AuthService();

  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // State
  bool _isLoading = false; // Controls spinner and button disable state
  bool _obscureText = true;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    disableFullScreen();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- CUSTOM STYLISH DIALOG ---
  void _showStylishDialog(String title, String message, {bool isError = true}) {
    // Choose icon and color based on the message type
    IconData icon = isError ? Icons.error_outline : Icons.check_circle_outline;
    Color color = isError ? Colors.red : Colors.green;

    if (title == "Connection Error") {
      icon = Icons.wifi_off_rounded;
      color = Colors.orange;
    } else if (title == "Login Failed" || title == "Input Error") {
      icon = Icons.lock_person_outlined;
      color = Colors.redAccent;
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 16,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon Bubble
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                // Message
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 25),
                // Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      "Okay",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- MAIN LOGIN LOGIC ---
  Future<void> _handleEmailPasswordLogin() async {
    // 1. Validate Form Inputs
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      _showStylishDialog("Input Error", "Please fix the errors in the form.");
      return;
    }

    // 2. Start Spinner & Disable Inputs
    setState(() {
      _isLoading = true;
    });

    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    try {
      // -----------------------------------------------------------------
      // STEP 1: Call the LOGIN endpoint
      // -----------------------------------------------------------------
      final loginResponse = await _authService.login(email, password);

      // Handle Null Response (Network Issues)
      if (loginResponse == null) {
        _showStylishDialog(
            "Connection Error", "Unable to connect to server. Check internet.");
        return;
      }

      // -----------------------------------------------------------------
      // STEP 2: Check Success & Onboarding
      // -----------------------------------------------------------------
      bool isSuccess = loginResponse['message'] == "Login successful" ||
          loginResponse['message'] ==
              "Login with temporary password successful";
      bool isOnboarding = loginResponse["onboardingRequired"] == true;

      // If NOT success AND NOT onboarding -> It's an error
      if (!isSuccess && !isOnboarding) {
        String backendMsg = loginResponse['message'] ??
            "Incorrect email or password. Please try again.";

        // Handle "Login failed" from server gracefully
        if (backendMsg.contains("Login failed") ||
            backendMsg.contains("Unexpected character")) {
          _showStylishDialog(
              "Login Failed", "Incorrect email or password. Please try again.");
        } else {
          _showStylishDialog("Login Failed", backendMsg);
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userEmail', email);

      // -----------------------------------------------------------------
      // STEP 3: Handle Onboarding / Resubmission
      // -----------------------------------------------------------------
      if (isOnboarding) {
        final int? idToPass =
            loginResponse["employeeId"] ?? loginResponse["userId"];
        final String onboardingMode = loginResponse["onboardingMode"] ?? "none";
        Map<String, dynamic>? existingProfile;

        if (onboardingMode == "resubmission" && idToPass != null) {
          existingProfile =
              await _authService.fetchRejectedProfileData(idToPass);
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => Emponboard(
              email: email,
              existingProfile: existingProfile,
              employeeId: idToPass,
            ),
          ),
        );
        return; // Stop execution here
      }

      // -----------------------------------------------------------------
      // STEP 4: Exchange Password for Token
      // -----------------------------------------------------------------
      final exchangeResponse =
          await _authService.exchangePasswordForToken(email, password);

      if (exchangeResponse == null || exchangeResponse['appToken'] == null) {
        _showStylishDialog(
            "Authentication Failed", "Could not verify credentials.");
        return;
      }

      // CRITICAL: Save Token BEFORE initializing FCM registration
      await prefs.setString('appToken', exchangeResponse['appToken']);
      // print("Token saved successfully.");

      // -----------------------------------------------------------------
      // STEP 5: Fetch Full Profile
      // -----------------------------------------------------------------
      int? userId = exchangeResponse["userId"];
      String role = exchangeResponse["userRole"] ?? "Employee";
      await prefs.setInt('userId', userId!);
      await prefs.setString('userRole', role);

      final fullProfile = await _authService.fetchFullEmployeeProfile(email);

      if (fullProfile != null) {
        await prefs.setInt('employeeId', fullProfile['EmployeeId']);
        await prefs.setString(
          'userName',
          "${fullProfile["FirstName"]} ${fullProfile["LastName"]}",
        );

        // Update Provider
        final userProfile = {
          "userId": userId,
          "employeeId": fullProfile["EmployeeId"],
          "firstName": fullProfile["FirstName"] ?? "",
          "middleName": fullProfile["MiddleName"] ?? "",
          "lastName": fullProfile["LastName"] ?? "",
          "gender": fullProfile["Gender"] ?? "",
          "email": fullProfile["Email"] ?? "",
          "mobileNumber": fullProfile["MobileNumber"] ?? "",
          "dateOfBirth": fullProfile["DateOfBirth"] ?? "",
          "street": fullProfile["Street"] ?? "",
          "city": fullProfile["City"] ?? "",
          "state": fullProfile["State"] ?? "",
          "postalCode": fullProfile["PostalCode"] ?? "",
          "country": fullProfile["Country"] ?? "",
          "employmentStatus": fullProfile["EmploymentStatus"] ?? "",
          "jobRole": fullProfile["JobRole"] ?? "",
          "userRole": role,
          "profilePicture": fullProfile["ProfilePicture"] ?? "",
          "bankAccountName": fullProfile["BankAccountName"] ?? "",
          "bankAccountNumber": fullProfile["BankAccountNumber"] ?? "",
          "bankBSB": fullProfile["BankBSB"] ?? "",
          "bankName": fullProfile["BankName"] ?? "",
          "nextOfKins": (fullProfile["NextOfKins"] as List<dynamic>? ?? []),
        };

        if (mounted) {
          Provider.of<UserProvider>(context, listen: false)
              .setUserProfile(userProfile);
        }

        // Enable Push Notifications
        try {
          // print("Initializing FCM for User: ${fullProfile["EmployeeId"]}");
          final notificationService = NotificationService();
          await notificationService.initializeFCM(
            employeeId: fullProfile["EmployeeId"],
            userTag: "user_${fullProfile["EmployeeId"]}",
          );
          final fcmToken = await FirebaseMessaging.instance.getToken();
          // print("MY FCM TOKEN: $fcmToken");
        } catch (fcmError) {
          print("FCM Init Warning: $fcmError");
        }
      } else {
        _showStylishDialog("Profile Error", "Could not load user profile.");
        return;
      }

      // -----------------------------------------------------------------
      // STEP 6: Navigation
      // -----------------------------------------------------------------
      if (!mounted) return;
      if (role == "Manager") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const Bottomnavbar(selectedIndex: 0)),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const EmpBottomnavbar()),
        );
      }
    } catch (e) {
      String errorStr = e.toString();
      // Handle "500 Login failed" crash pattern gracefully
      if (errorStr.contains("Login failed") ||
          errorStr.contains("Unexpected character")) {
        _showStylishDialog("Login Failed", "Incorrect email or password.");
      } else {
        _showStylishDialog(
            "System Error", "An unexpected error occurred: $errorStr");
      }
    } finally {
      // 3. Stop Spinner (Always runs regardless of success/fail)
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final logoSize = size.width * 0.5;
    final paddingUnit = size.width * 0.03;

    return Scaffold(
        backgroundColor: const Color(0xFF2F3846),
        body: Stack(children: [
          const Positioned.fill(child: LoginBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(paddingUnit * 2),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    children: [
                      Image(
                        image: const AssetImage('assets/logo.png'),
                        width: logoSize,
                        height: logoSize,
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(136, 42, 41, 41)
                                  .withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  spreadRadius: 2,
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Login",
                                  style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                const SizedBox(height: 20),

                                // Email Field
                                const Text("Email",
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 16)),
                                const SizedBox(height: 5),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  enabled: !_isLoading, // Disable while loading
                                  style: const TextStyle(
                                      color: Color.fromARGB(255, 32, 32, 32)),
                                  decoration: InputDecoration(
                                    hintText: "username@gmail.com",
                                    hintStyle:
                                        const TextStyle(color: Colors.grey),
                                    filled: true,
                                    fillColor: const Color.fromARGB(
                                        255, 255, 255, 255),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter an email';
                                    }
                                    const emailRegex =
                                        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
                                    if (!RegExp(emailRegex).hasMatch(value)) {
                                      return 'Please enter a valid email address';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 15),

                                // Password Field
                                const Text("Password",
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 16)),
                                const SizedBox(height: 5),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscureText,
                                  enabled: !_isLoading, // Disable while loading
                                  style: const TextStyle(
                                      color: Color.fromARGB(255, 17, 17, 17)),
                                  decoration: InputDecoration(
                                    hintText: "Password",
                                    hintStyle:
                                        const TextStyle(color: Colors.grey),
                                    filled: true,
                                    fillColor: const Color.fromARGB(
                                        255, 255, 255, 255),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureText
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () => setState(
                                          () => _obscureText = !_obscureText),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your password';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),

                                // Forgot Password Link
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (context) =>
                                                      const ForgotPasswordScreen()),
                                            );
                                          },
                                    child: const Text("Forgot Password?",
                                        style:
                                            TextStyle(color: Colors.white70)),
                                  ),
                                ),
                                const SizedBox(height: 15),

                                // Login Button with Spinner
                                Center(
                                  child: SizedBox(
                                    width: size.width * 0.7,
                                    height:
                                        50, // Fixed height keeps layout stable during loading
                                    child: ElevatedButton(
                                      onPressed: _isLoading
                                          ? null // Disable prevents double clicks
                                          : _handleEmailPasswordLogin,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF2979FF),
                                        // Gray out button when disabled/loading
                                        disabledBackgroundColor:
                                            const Color(0xFF2979FF)
                                                .withOpacity(0.6),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 0, horizontal: 0),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : const Text("Log In",
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.white)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 25),
                                // Clean layout at the bottom (Social buttons removed)
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]));
  }
}
