import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart'; // BIOMETRIC VERSION: Import for Face ID/Touch ID
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
  
  // BIOMETRIC VERSION: Initialize Local Authentication for Face ID/Touch ID
  final LocalAuthentication _localAuth = LocalAuthentication();

  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // State
  bool _obscureText = true;
  bool _isLoading = false; // BASE VERSION: Added loading state variable to track login process
  final _formKey = GlobalKey<FormState>();
  
  // BIOMETRIC VERSION: State variables for biometric authentication
  bool _canUseBiometric = false; // Can device support biometric?
  bool _isBiometricEnabled = false; // Has user logged in before?
  bool _showBiometricButton = false; // Show Face ID button on UI?

  @override
  void initState() {
    super.initState();
    disableFullScreen();
    
    // BIOMETRIC VERSION: Check if biometric login is available when screen loads
    _checkBiometricAvailability();
  }

  // BIOMETRIC VERSION: Check if device supports biometric and if user has previously logged in
  Future<void> _checkBiometricAvailability() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if device can use biometric authentication (Face ID/Touch ID/Fingerprint)
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      
      // Check if user has previously logged in successfully
      final hasLoggedInBefore = prefs.getString('lastBiometricEmail') != null;
      
      // BIOMETRIC VERSION: Check if the last biometric login is still valid (within 1 hour)
      final lastLoginTime = prefs.getInt('lastBiometricLoginTime');
      final isSessionValid = lastLoginTime != null && 
          DateTime.now().millisecondsSinceEpoch - lastLoginTime < 3600000; // 1 hour = 3600000 ms
      
      setState(() {
        _canUseBiometric = canCheckBiometrics && isDeviceSupported;
        _isBiometricEnabled = hasLoggedInBefore;
        // Show biometric button only if device supports it, user logged in before, and session is valid
        _showBiometricButton = _canUseBiometric && _isBiometricEnabled && isSessionValid;
      });
      
      // BIOMETRIC VERSION: Auto-fill email if biometric is available
      if (_showBiometricButton) {
        final savedEmail = prefs.getString('lastBiometricEmail');
        if (savedEmail != null) {
          _emailController.text = savedEmail;
        }
      }
      
    } catch (e) {
      print("BIOMETRIC VERSION: Error checking availability: $e");
    }
  }

  // BIOMETRIC VERSION: Handle Face ID/Touch ID authentication
  Future<void> _handleBiometricLogin() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // BIOMETRIC VERSION: Check if session is still valid (within 1 hour)
      final lastLoginTime = prefs.getInt('lastBiometricLoginTime');
      if (lastLoginTime == null || 
          DateTime.now().millisecondsSinceEpoch - lastLoginTime >= 3600000) {
        // Session expired, require password login
        setState(() {
          _isLoading = false;
          _showBiometricButton = false;
        });
        _showSnackBar("Biometric session expired. Please login with password.");
        return;
      }
      
      // BIOMETRIC VERSION: Trigger Face ID/Touch ID/Fingerprint prompt
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to login to ShiftSmart',
        options: const AuthenticationOptions(
          stickyAuth: true, // Keep auth dialog until success or cancel
          biometricOnly: true, // Only use biometric, no PIN fallback
        ),
      );

      if (!authenticated) {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar("Biometric authentication failed");
        return;
      }

      // BIOMETRIC VERSION: Retrieve saved credentials after successful biometric authentication
      final savedEmail = prefs.getString('lastBiometricEmail');
      final savedToken = prefs.getString('appToken');
      final savedUserId = prefs.getInt('userId');
      final savedRole = prefs.getString('userRole');

      if (savedEmail == null || savedToken == null || savedUserId == null) {
        setState(() {
          _isLoading = false;
          _showBiometricButton = false;
        });
        _showSnackBar("Session expired. Please login with password.");
        return;
      }

      // BIOMETRIC VERSION: Fetch fresh profile data
      final fullProfile = await _authService.fetchFullEmployeeProfile(savedEmail);

      if (fullProfile != null) {
        // Update user provider with latest data
        final userProfile = {
          "userId": savedUserId,
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
          "userRole": savedRole ?? "Employee",
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

        // Navigate to appropriate screen based on role
        if (mounted) {
          if (savedRole == "Manager") {
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
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar("Could not load profile. Please login again.");
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar("Biometric login error: $e");
      print("BIOMETRIC VERSION: Login Exception: $e");
    }
  }

  // BOTH VERSIONS: Main Login Logic
  void _handleEmailPasswordLogin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    // BASE VERSION: Removed snackbar notification for validation errors
    // Now only shows red text below fields when empty or invalid
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return; // Just return - let field errors display below the fields
    }

    // BASE VERSION: Set loading state to true when login starts
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Call Login Endpoint
      final loginResponse = await _authService.login(email, password);

      // BASE VERSION: Set loading to false before showing error
      if (loginResponse == null) {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar("Unable to connect to server.");
        return;
      }

      // 2. Error Handling
      bool isSuccess = loginResponse['message'] == "Login successful" ||
          loginResponse['message'] ==
              "Login with temporary password successful";
      bool isOnboarding = loginResponse["onboardingRequired"] == true;

      // BASE VERSION: Handle incorrect password/credentials from server
      // Shows SnackBar notification with server error message
      if (!isSuccess && !isOnboarding) {
        String backendMsg =
            loginResponse['message'] ?? "An unexpected error occurred.";
        
        setState(() {
          _isLoading = false;
        });
        
        // BASE VERSION: Check for specific error messages and show user-friendly text
        if (backendMsg.toLowerCase().contains('password') || 
            backendMsg.toLowerCase().contains('credentials') ||
            backendMsg.toLowerCase().contains('invalid')) {
          _showSnackBar("Incorrect password. Please try again.");
        } else {
          _showSnackBar(backendMsg);
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userEmail', email);

      // 3. Handle Onboarding / Resubmission
      if (isOnboarding) {
        final int? idToPass =
            loginResponse["employeeId"] ?? loginResponse["userId"];
        final String onboardingMode = loginResponse["onboardingMode"] ?? "none";
        Map<String, dynamic>? existingProfile;

        if (onboardingMode == "resubmission" && idToPass != null) {
          existingProfile =
              await _authService.fetchRejectedProfileData(idToPass);
        }

        if (mounted) {
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
        }
        return;
      }

      // 4. Exchange Password for Token
      final exchangeResponse =
          await _authService.exchangePasswordForToken(email, password);

      if (exchangeResponse == null || exchangeResponse['appToken'] == null) {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar("Authentication failed.");
        return;
      }

      // CRITICAL: Save Token BEFORE initializing FCM registration
      await prefs.setString('appToken', exchangeResponse['appToken']);
      print("Token saved successfully.");

      // 5. Fetch Full Profile
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

        // BIOMETRIC VERSION: Save credentials for future biometric login after successful password login
        await prefs.setString('lastBiometricEmail', email);
        // BIOMETRIC VERSION: Save current timestamp for 1-hour session validation
        await prefs.setInt('lastBiometricLoginTime', DateTime.now().millisecondsSinceEpoch);
        print("BIOMETRIC VERSION: Credentials saved for future biometric login");

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
          print("Initializing FCM for User: ${fullProfile["EmployeeId"]}");
          final notificationService = NotificationService();
          await notificationService.initializeFCM(
            employeeId: fullProfile["EmployeeId"],
            userTag: "user_${fullProfile["EmployeeId"]}",
          );
          final fcmToken = await FirebaseMessaging.instance.getToken();
          print("MY FCM TOKEN: $fcmToken");
        } catch (fcmError) {
          print("FCM Init Warning: $fcmError");
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar("Could not load profile.");
        return;
      }

      // 6. Navigation
      if (mounted) {
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
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar("Login Error: $e");
      print("Login Exception: $e");
    }
  }

  // BASE VERSION: Enhanced SnackBar styling for better visibility
  // Shows red notification at bottom of screen for server errors
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
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
                  // BASE VERSION: Disabled auto-validation
                  // Errors only show when user clicks "Log In" button
                  autovalidateMode: AutovalidateMode.disabled,
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
                                
                                // BIOMETRIC VERSION: Show Face ID/Touch ID button if available and session is valid
                                if (_showBiometricButton) ...[
                                  Center(
                                    child: Column(
                                      children: [
                                        // BIOMETRIC VERSION: Face ID icon button
                                        IconButton(
                                          onPressed: _isLoading ? null : _handleBiometricLogin,
                                          icon: const Icon(
                                            Icons.fingerprint,
                                            size: 64,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          "Login with Face ID / Touch ID",
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        const Row(
                                          children: [
                                            Expanded(
                                                child: Divider(
                                                    color: Colors.white38,
                                                    thickness: 1)),
                                            Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 8.0),
                                              child: Text("Or use password",
                                                  style: TextStyle(color: Colors.white)),
                                            ),
                                            Expanded(
                                                child: Divider(
                                                    color: Colors.white38,
                                                    thickness: 1)),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                      ],
                                    ),
                                  ),
                                ],
                                
                                // Email Field
                                const Text("Email",
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 16)),
                                const SizedBox(height: 5),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  style: const TextStyle(
                                      color: Color.fromARGB(255, 32, 32, 32)),
                                  decoration: InputDecoration(
                                    hintText: "username@gmail.com",
                                    hintStyle:
                                        const TextStyle(color: Colors.grey),
                                    filled: true,
                                    fillColor: const Color.fromARGB(
                                        255, 255, 255, 255),
                                    // BASE VERSION: White borders for all states
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white, width: 2)),
                                    errorBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white)),
                                    focusedErrorBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white, width: 2)),
                                    // BASE VERSION: Bold red error text with white stroke/shadow effect
                                    errorStyle: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                  // BASE VERSION: Email validation
                                  // Shows error below field only when form is submitted
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
                                  style: const TextStyle(
                                      color: Color.fromARGB(255, 17, 17, 17)),
                                  decoration: InputDecoration(
                                    hintText: "Password",
                                    hintStyle:
                                        const TextStyle(color: Colors.grey),
                                    filled: true,
                                    fillColor: const Color.fromARGB(
                                        255, 255, 255, 255),
                                    // BASE VERSION: White borders for all states
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white, width: 2)),
                                    errorBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white)),
                                    focusedErrorBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Colors.white, width: 2)),
                                    // BASE VERSION: Bold red error text with white stroke/shadow effect
                                    errorStyle: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
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
                                  // BASE VERSION: Password validation
                                  // Shows error below field only when form is submitted
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your password';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () {
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
                                Center(
                                  child: SizedBox(
                                    width: size.width * 0.7,
                                    child: ElevatedButton(
                                      // BASE VERSION: Disable button when loading
                                      onPressed: _isLoading ? null : _handleEmailPasswordLogin,
                                      style: ElevatedButton.styleFrom(
                                        // BASE VERSION: Change button color to grey when loading
                                        backgroundColor:
                                            _isLoading ? Colors.grey : const Color(0xFF2979FF),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16, horizontal: 0),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                      // BASE VERSION: Show loading spinner when logging in
                                      child: _isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text("Log In",
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.white)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 15),

                                const Row(
                                  children: [
                                    Expanded(
                                        child: Divider(
                                            color: Colors.white38,
                                            thickness: 1)),
                                    Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 8.0),
                                      child: Text("Or Sign In With",
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ),
                                    Expanded(
                                        child: Divider(
                                            color: Colors.white38,
                                            thickness: 1)),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Social Buttons (Placeholders)
                                Center(
                                  child: SizedBox(
                                    width: size.width * 0.8,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () {},
                                            icon: Image.network(
                                              'https://img.icons8.com/?size=100&id=17949&format=png&color=000000',
                                              height: 24,
                                              width: 24,
                                            ),
                                            label: const Text("Google"),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: Colors.black,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () {},
                                            icon: Image.network(
                                              'https://img.icons8.com/?size=100&id=22989&format=png&color=000000',
                                              height: 24,
                                              width: 24,
                                            ),
                                            label: const Text("Microsoft"),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: Colors.black,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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






















// import 'dart:ui';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:shiftsmart/providers/user_provider.dart';
// import 'package:shiftsmart/screens/employee/empOnboard.dart';
// import 'package:shiftsmart/screens/forgot_password.dart';
// import 'package:shiftsmart/services/auth_service.dart';
// import 'package:shiftsmart/services/notification_service.dart';
// import 'package:shiftsmart/utils/fullscreen_helper.dart';
// import 'package:shiftsmart/widgets/bottomnavbar.dart';
// import 'package:shiftsmart/widgets/emp_bottomnavbar.dart';
// import 'package:shiftsmart/widgets/loginBackground.dart';

// class Login extends StatefulWidget {
//   const Login({super.key});

//   @override
//   State<Login> createState() => _LoginState();
// }

// class _LoginState extends State<Login> {
//   final AuthService _authService = AuthService();

//   // Controllers
//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _passwordController = TextEditingController();

//   // State
//   bool _obscureText = true;
//   bool _isLoading = false; // CHANGE 1: Added loading state variable to track login process
//   final _formKey = GlobalKey<FormState>();

//   @override
//   void initState() {
//     super.initState();
//     disableFullScreen();
//   }

//   // Main Login Logic
//   void _handleEmailPasswordLogin() async {
//     String email = _emailController.text.trim();
//     String password = _passwordController.text.trim();

//     // CHANGE 2: Removed snackbar notification for validation errors
//     // Now only shows red text below fields when empty or invalid
//     if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
//       return; // Just return - let field errors display below the fields
//     }

//     // CHANGE 3: Set loading state to true when login starts
//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       // 1. Call Login Endpoint
//       final loginResponse = await _authService.login(email, password);

//       // CHANGE 4: Set loading to false before showing error
//       if (loginResponse == null) {
//         setState(() {
//           _isLoading = false;
//         });
//         _showSnackBar("Unable to connect to server.");
//         return;
//       }

//       // 2. Error Handling
//       bool isSuccess = loginResponse['message'] == "Login successful" ||
//           loginResponse['message'] ==
//               "Login with temporary password successful";
//       bool isOnboarding = loginResponse["onboardingRequired"] == true;

//       // CHANGE 5: Handle incorrect password/credentials from server
//       // Shows SnackBar notification with server error message
//       if (!isSuccess && !isOnboarding) {
//         String backendMsg =
//             loginResponse['message'] ?? "An unexpected error occurred.";
        
//         setState(() {
//           _isLoading = false;
//         });
        
//         // CHANGE 6: Check for specific error messages and show user-friendly text
//         if (backendMsg.toLowerCase().contains('password') || 
//             backendMsg.toLowerCase().contains('credentials') ||
//             backendMsg.toLowerCase().contains('invalid')) {
//           _showSnackBar("Incorrect password. Please try again.");
//         } else {
//           _showSnackBar(backendMsg);
//         }
//         return;
//       }

//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('userEmail', email);

//       // 3. Handle Onboarding / Resubmission
//       if (isOnboarding) {
//         final int? idToPass =
//             loginResponse["employeeId"] ?? loginResponse["userId"];
//         final String onboardingMode = loginResponse["onboardingMode"] ?? "none";
//         Map<String, dynamic>? existingProfile;

//         if (onboardingMode == "resubmission" && idToPass != null) {
//           existingProfile =
//               await _authService.fetchRejectedProfileData(idToPass);
//         }

//         if (mounted) {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(
//               builder: (context) => Emponboard(
//                 email: email,
//                 existingProfile: existingProfile,
//                 employeeId: idToPass,
//               ),
//             ),
//           );
//         }
//         return;
//       }

//       // 4. Exchange Password for Token
//       final exchangeResponse =
//           await _authService.exchangePasswordForToken(email, password);

//       if (exchangeResponse == null || exchangeResponse['appToken'] == null) {
//         setState(() {
//           _isLoading = false;
//         });
//         _showSnackBar("Authentication failed.");
//         return;
//       }

//       // CRITICAL: Save Token BEFORE initializing FCM registration
//       await prefs.setString('appToken', exchangeResponse['appToken']);
//       print("Token saved successfully.");

//       // 5. Fetch Full Profile
//       int? userId = exchangeResponse["userId"];
//       String role = exchangeResponse["userRole"] ?? "Employee";
//       await prefs.setInt('userId', userId!);
//       await prefs.setString('userRole', role);

//       final fullProfile = await _authService.fetchFullEmployeeProfile(email);

//       if (fullProfile != null) {
//         await prefs.setInt('employeeId', fullProfile['EmployeeId']);
//         await prefs.setString(
//           'userName',
//           "${fullProfile["FirstName"]} ${fullProfile["LastName"]}",
//         );

//         // Update Provider
//         final userProfile = {
//           "userId": userId,
//           "employeeId": fullProfile["EmployeeId"],
//           "firstName": fullProfile["FirstName"] ?? "",
//           "middleName": fullProfile["MiddleName"] ?? "",
//           "lastName": fullProfile["LastName"] ?? "",
//           "gender": fullProfile["Gender"] ?? "",
//           "email": fullProfile["Email"] ?? "",
//           "mobileNumber": fullProfile["MobileNumber"] ?? "",
//           "dateOfBirth": fullProfile["DateOfBirth"] ?? "",
//           "street": fullProfile["Street"] ?? "",
//           "city": fullProfile["City"] ?? "",
//           "state": fullProfile["State"] ?? "",
//           "postalCode": fullProfile["PostalCode"] ?? "",
//           "country": fullProfile["Country"] ?? "",
//           "employmentStatus": fullProfile["EmploymentStatus"] ?? "",
//           "jobRole": fullProfile["JobRole"] ?? "",
//           "userRole": role,
//           "profilePicture": fullProfile["ProfilePicture"] ?? "",
//           "bankAccountName": fullProfile["BankAccountName"] ?? "",
//           "bankAccountNumber": fullProfile["BankAccountNumber"] ?? "",
//           "bankBSB": fullProfile["BankBSB"] ?? "",
//           "bankName": fullProfile["BankName"] ?? "",
//           "nextOfKins": (fullProfile["NextOfKins"] as List<dynamic>? ?? []),
//         };

//         if (mounted) {
//           Provider.of<UserProvider>(context, listen: false)
//               .setUserProfile(userProfile);
//         }

//         // Enable Push Notifications
//         try {
//           print("Initializing FCM for User: ${fullProfile["EmployeeId"]}");
//           final notificationService = NotificationService();
//           // Since we are logged in, we pass the real EmployeeId.
//           // Because ID != 0, it will proceed to register with the backend using the saved AppToken.
//           await notificationService.initializeFCM(
//             employeeId: fullProfile["EmployeeId"],
//             userTag: "user_${fullProfile["EmployeeId"]}",
//           );
//           final fcmToken = await FirebaseMessaging.instance.getToken();
//           print("MY FCM TOKEN: $fcmToken");
//         } catch (fcmError) {
//           print("FCM Init Warning: $fcmError");
//         }
//       } else {
//         setState(() {
//           _isLoading = false;
//         });
//         _showSnackBar("Could not load profile.");
//         return;
//       }

//       // 6. Navigation
//       if (mounted) {
//         if (role == "Manager") {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(
//                 builder: (context) => const Bottomnavbar(selectedIndex: 0)),
//           );
//         } else {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(builder: (context) => const EmpBottomnavbar()),
//           );
//         }
//       }
//     } catch (e) {
//       setState(() {
//         _isLoading = false;
//       });
//       _showSnackBar("Login Error: $e");
//       print("Login Exception: $e");
//     }
//   }

//   // CHANGE 7: Enhanced SnackBar styling for better visibility
//   // Shows red notification at bottom of screen for server errors
//   void _showSnackBar(String message) {
//     if (mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text(
//             message,
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 16,
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//           backgroundColor: Colors.red,
//           behavior: SnackBarBehavior.floating,
//           margin: const EdgeInsets.all(16),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(10),
//           ),
//           duration: const Duration(seconds: 4),
//           action: SnackBarAction(
//             label: 'OK',
//             textColor: Colors.white,
//             onPressed: () {
//               ScaffoldMessenger.of(context).hideCurrentSnackBar();
//             },
//           ),
//         ),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final size = MediaQuery.of(context).size;
//     final logoSize = size.width * 0.5;
//     final paddingUnit = size.width * 0.03;

//     return Scaffold(
//         backgroundColor: const Color(0xFF2F3846),
//         body: Stack(children: [
//           const Positioned.fill(child: LoginBackground()),
//           SafeArea(
//             child: Center(
//               child: SingleChildScrollView(
//                 padding: EdgeInsets.all(paddingUnit * 2),
//                 child: Form(
//                   key: _formKey,
//                   // CHANGE 8: Disabled auto-validation
//                   // Errors only show when user clicks "Log In" button
//                   autovalidateMode: AutovalidateMode.disabled,
//                   child: Column(
//                     children: [
//                       Image(
//                         image: const AssetImage('assets/logo.png'),
//                         width: logoSize,
//                         height: logoSize,
//                       ),
//                       ClipRRect(
//                         borderRadius: BorderRadius.circular(20),
//                         child: BackdropFilter(
//                           filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
//                           child: Container(
//                             padding: const EdgeInsets.all(20),
//                             decoration: BoxDecoration(
//                               color: const Color.fromARGB(136, 42, 41, 41)
//                                   .withOpacity(0.6),
//                               borderRadius: BorderRadius.circular(20),
//                               border: Border.all(color: Colors.white),
//                               boxShadow: [
//                                 BoxShadow(
//                                   color: Colors.black.withOpacity(0.2),
//                                   spreadRadius: 2,
//                                   blurRadius: 8,
//                                   offset: const Offset(0, 4),
//                                 ),
//                               ],
//                             ),
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               children: [
//                                 const Text(
//                                   "Login",
//                                   style: TextStyle(
//                                       fontSize: 28,
//                                       fontWeight: FontWeight.bold,
//                                       color: Colors.white),
//                                 ),
//                                 const SizedBox(height: 20),
//                                 // Email Field
//                                 const Text("Email",
//                                     style: TextStyle(
//                                         color: Colors.white, fontSize: 16)),
//                                 const SizedBox(height: 5),
//                                 TextFormField(
//                                   controller: _emailController,
//                                   keyboardType: TextInputType.emailAddress,
//                                   style: const TextStyle(
//                                       color: Color.fromARGB(255, 32, 32, 32)),
//                                   decoration: InputDecoration(
//                                     hintText: "username@gmail.com",
//                                     hintStyle:
//                                         const TextStyle(color: Colors.grey),
//                                     filled: true,
//                                     fillColor: const Color.fromARGB(
//                                         255, 255, 255, 255),
//                                     // CHANGE 9: White borders for all states
//                                     border: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white)),
//                                     enabledBorder: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white)),
//                                     focusedBorder: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white, width: 2)),
//                                     errorBorder: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white)),
//                                     focusedErrorBorder: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white, width: 2)),
//                                     // CHANGE 10: Bold red error text with white stroke/shadow effect
//                                     errorStyle: const TextStyle(
//                                       color: Colors.red,
//                                       fontWeight: FontWeight.w900,
//                                       fontSize: 13,
                                      
//                                     ),
//                                   ),
//                                   // CHANGE 11: Email validation
//                                   // Shows error below field only when form is submitted
//                                   validator: (value) {
//                                     if (value == null || value.isEmpty) {
//                                       return 'Please enter an email';
//                                     }
//                                     const emailRegex =
//                                         r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
//                                     if (!RegExp(emailRegex).hasMatch(value)) {
//                                       return 'Please enter a valid email address';
//                                     }
//                                     return null;
//                                   },
//                                 ),
//                                 const SizedBox(height: 15),
//                                 // Password Field
//                                 const Text("Password",
//                                     style: TextStyle(
//                                         color: Colors.white, fontSize: 16)),
//                                 const SizedBox(height: 5),
//                                 TextFormField(
//                                   controller: _passwordController,
//                                   obscureText: _obscureText,
//                                   style: const TextStyle(
//                                       color: Color.fromARGB(255, 17, 17, 17)),
//                                   decoration: InputDecoration(
//                                     hintText: "Password",
//                                     hintStyle:
//                                         const TextStyle(color: Colors.grey),
//                                     filled: true,
//                                     fillColor: const Color.fromARGB(
//                                         255, 255, 255, 255),
//                                     // CHANGE 12: White borders for all states
//                                     border: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white)),
//                                     enabledBorder: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white)),
//                                     focusedBorder: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white, width: 2)),
//                                     errorBorder: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white)),
//                                     focusedErrorBorder: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12),
//                                         borderSide: const BorderSide(color: Colors.white, width: 2)),
//                                     // CHANGE 13: Bold red error text with white stroke/shadow effect
//                                     errorStyle: const TextStyle(
//                                       color: Colors.red,
//                                       fontWeight: FontWeight.w900,
//                                       fontSize: 13,
                                      
//                                     ),
//                                     suffixIcon: IconButton(
//                                       icon: Icon(
//                                         _obscureText
//                                             ? Icons.visibility_off
//                                             : Icons.visibility,
//                                         color: Colors.grey,
//                                       ),
//                                       onPressed: () => setState(
//                                           () => _obscureText = !_obscureText),
//                                     ),
//                                   ),
//                                   // CHANGE 14: Password validation
//                                   // Shows error below field only when form is submitted
//                                   validator: (value) {
//                                     if (value == null || value.isEmpty) {
//                                       return 'Please enter your password';
//                                     }
//                                     return null;
//                                   },
//                                 ),
//                                 const SizedBox(height: 10),
//                                 Align(
//                                   alignment: Alignment.centerLeft,
//                                   child: TextButton(
//                                     onPressed: () {
//                                       Navigator.push(
//                                         context,
//                                         MaterialPageRoute(
//                                             builder: (context) =>
//                                                 const ForgotPasswordScreen()),
//                                       );
//                                     },
//                                     child: const Text("Forgot Password?",
//                                         style:
//                                             TextStyle(color: Colors.white70)),
//                                   ),
//                                 ),
//                                 const SizedBox(height: 15),
//                                 Center(
//                                   child: SizedBox(
//                                     width: size.width * 0.7,
//                                     child: ElevatedButton(
//                                       // CHANGE 15: Disable button when loading
//                                       onPressed: _isLoading ? null : _handleEmailPasswordLogin,
//                                       style: ElevatedButton.styleFrom(
//                                         // CHANGE 16: Change button color to grey when loading
//                                         backgroundColor:
//                                             _isLoading ? Colors.grey : const Color(0xFF2979FF),
//                                         padding: const EdgeInsets.symmetric(
//                                             vertical: 16, horizontal: 0),
//                                         shape: RoundedRectangleBorder(
//                                             borderRadius:
//                                                 BorderRadius.circular(10)),
//                                       ),
//                                       // CHANGE 17: Show loading spinner when logging in
//                                       child: _isLoading
//                                           ? const SizedBox(
//                                               height: 20,
//                                               width: 20,
//                                               child: CircularProgressIndicator(
//                                                 color: Colors.white,
//                                                 strokeWidth: 2,
//                                               ),
//                                             )
//                                           : const Text("Log In",
//                                               style: TextStyle(
//                                                   fontSize: 16,
//                                                   color: Colors.white)),
//                                     ),
//                                   ),
//                                 ),
//                                 const SizedBox(height: 15),

//                                 const Row(
//                                   children: [
//                                     Expanded(
//                                         child: Divider(
//                                             color: Colors.white38,
//                                             thickness: 1)),
//                                     Padding(
//                                       padding:
//                                           EdgeInsets.symmetric(horizontal: 8.0),
//                                       child: Text("Or Sign In With",
//                                           style:
//                                               TextStyle(color: Colors.white)),
//                                     ),
//                                     Expanded(
//                                         child: Divider(
//                                             color: Colors.white38,
//                                             thickness: 1)),
//                                   ],
//                                 ),
//                                 const SizedBox(height: 20),

//                                 // Social Buttons (Placeholders)
//                                 Center(
//                                   child: SizedBox(
//                                     width: size.width * 0.8,
//                                     child: Row(
//                                       mainAxisAlignment:
//                                           MainAxisAlignment.spaceEvenly,
//                                       children: [
//                                         Expanded(
//                                           child: ElevatedButton.icon(
//                                             onPressed: () {},
//                                             icon: Image.network(
//                                               'https://img.icons8.com/?size=100&id=17949&format=png&color=000000',
//                                               height: 24,
//                                               width: 24,
//                                             ),
//                                             label: const Text("Google"),
//                                             style: ElevatedButton.styleFrom(
//                                               backgroundColor: Colors.white,
//                                               foregroundColor: Colors.black,
//                                               padding:
//                                                   const EdgeInsets.symmetric(
//                                                       horizontal: 16,
//                                                       vertical: 12),
//                                               shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(
//                                                           20)),
//                                             ),
//                                           ),
//                                         ),
//                                         const SizedBox(width: 16),
//                                         Expanded(
//                                           child: ElevatedButton.icon(
//                                             onPressed: () {},
//                                             icon: Image.network(
//                                               'https://img.icons8.com/?size=100&id=22989&format=png&color=000000',
//                                               height: 24,
//                                               width: 24,
//                                             ),
//                                             label: const Text("Microsoft"),
//                                             style: ElevatedButton.styleFrom(
//                                               backgroundColor: Colors.white,
//                                               foregroundColor: Colors.black,
//                                               padding:
//                                                   const EdgeInsets.symmetric(
//                                                       horizontal: 16,
//                                                       vertical: 12),
//                                               shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(
//                                                           20)),
//                                             ),
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ]));
//   }
// }



































// // lib/screens/login.dart
// import 'dart:ui';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart'; // Import Response
// import 'package:shiftsmart/screens/employee/empOnboard.dart';
// import 'package:shiftsmart/services/auth_service.dart';
// import 'package:shiftsmart/services/notification_service.dart';
// // import 'package:shiftsmart/services/flutterauth.dart';
// import 'package:shiftsmart/utils/fullscreen_helper.dart';
// import 'package:shiftsmart/widgets/bottomnavbar.dart';
// import 'package:shiftsmart/widgets/emp_bottomnavbar.dart';
// import 'package:provider/provider.dart';
// import 'package:shiftsmart/providers/user_provider.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:shiftsmart/widgets/loginBackground.dart';
// import 'package:shiftsmart/screens/forgot_password.dart';

// class Login extends StatefulWidget {
//   const Login({super.key});

//   @override
//   State<Login> createState() => _LoginState();
// }

// class _LoginState extends State<Login> {
//   final AuthService _authService = AuthService();
//   // final Flutterauth _flutterauth = Flutterauth();

//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _passwordController = TextEditingController();

//   bool isLoggedIn = false;
//   String? accessToken;
//   bool _obscureText = true;
//   String? userName;
//   String? userEmail;
//   final _formKey = GlobalKey<FormState>();

//   @override
//   void initState() {
//     super.initState();
//     disableFullScreen();
//   }

//   // --- REVERTED LOGIN LOGIC ---
//   // void _handleEmailPasswordLogin() async {
//   //   String email = _emailController.text.trim();
//   //   String password = _passwordController.text.trim();

//   //   if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
//   //     _showSnackBar("Please fix the errors in the form.");
//   //     return;
//   //   }

//   //   try {
//   //     // -----------------------------------------------------------------
//   //     // STEP 1: Call the LOGIN endpoint
//   //     // -----------------------------------------------------------------
//   //     final loginResponse = await _authService.login(email, password);
//   //     print("Login Response in UI: $loginResponse");

//   //     // Check for null response or if the 'Message' key exists (indicating an error)
//   //     if (loginResponse == null || loginResponse.containsKey('Message')) {
//   //       String errorMessage = loginResponse?['Message'] ??
//   //           "Login failed. Please check your credentials.";
//   //       _showSnackBar(errorMessage);
//   //       return;
//   //     }
//   //     // Although AuthService handles non-200, double-check successful message just in case
//   //     if (loginResponse['message'] != "Login successful" &&
//   //         loginResponse['message'] !=
//   //             "Login with temporary password successful") {
//   //       _showSnackBar(loginResponse['message'] ??
//   //           "An unexpected error occurred during login.");
//   //       return;
//   //     }

//   //     final prefs = await SharedPreferences.getInstance();
//   //     await prefs.setString('userEmail', email);
//   //     print("User Email stored: $email");

//   //     // -----------------------------------------------------------------
//   //     // STEP 2: Check ONBOARDING flags (ORIGINAL LOGIC)
//   //     // -----------------------------------------------------------------
//   //     // Default to false (complete) if null, as per original plan
//   //     final bool onboardingRequired =
//   //         loginResponse["onboardingRequired"] ?? false;
//   //     final String onboardingMode = loginResponse["onboardingMode"] ?? "none";

//   //     // *** ORIGINAL LOGIC: If onboardingRequired is TRUE, go to onboarding ***
//   //     if (onboardingRequired) {
//   //       print("Onboarding required. Mode: $onboardingMode");

//   //       Map<String, dynamic>? existingProfile;

//   //       if (onboardingMode == "resubmission") {
//   //         print("Resubmission mode: Fetching rejected items.");
//   //         final int? employeeId = loginResponse["employeeId"];

//   //         if (employeeId != null) {
//   //           existingProfile =
//   //               await _authService.fetchRejectedProfileData(employeeId);
//   //           if (existingProfile == null) {
//   //             _showSnackBar(
//   //                 "Could not load resubmission data. Please contact support.");
//   //             return;
//   //           }
//   //         } else {
//   //           _showSnackBar("Could not get Employee ID for resubmission.");
//   //           return;
//   //         }
//   //       }

//   //       Navigator.pushReplacement(
//   //         context,
//   //         MaterialPageRoute(
//   //           builder: (context) => Emponboard(
//   //             email: email,
//   //             rejectionReason: loginResponse['rejectionReason'],
//   //             existingProfile: existingProfile,
//   //           ),
//   //         ),
//   //       );
//   //       return; // Stop execution
//   //     }

//   //     // *** ORIGINAL LOGIC: If onboardingRequired is FALSE, user is active ***
//   //     // -----------------------------------------------------------------
//   //     // STEP 3: User is active. Exchange password for a token.
//   //     // -----------------------------------------------------------------
//   //     print("User is active. Exchanging password for token.");
//   //     final exchangeResponse =
//   //         await _authService.exchangePasswordForToken(email, password);

//   //     if (exchangeResponse == null || exchangeResponse['appToken'] == null) {
//   //       _showSnackBar(exchangeResponse?['Message'] ?? "Authentication failed");
//   //       return;
//   //     }

//   //     print("Token received. Proceeding to fetch profile.");
//   //     // -----------------------------------------------------------------
//   //     if (exchangeResponse['appToken'] != null) {
//   //       // We reuse the 'prefs' instance you created earlier at the top of the function
//   //       await prefs.setString('appToken', exchangeResponse['appToken']);
//   //       print("✅ Token saved to SharedPreferences: appToken");
//   //     } else {
//   //       print("⚠️ Warning: AppToken was null in exchange response");
//   //     }
//   //     // -----------------------------------------------------------------
//   //     // STEP 4: Token is saved. Now fetch profile and navigate.
//   //     // -----------------------------------------------------------------
//   //     int? userId = exchangeResponse["userId"];
//   //     String role = exchangeResponse["userRole"] ??
//   //         "Unknown"; // Use role from exchange response
//   //     await prefs.setInt('userId', userId!);
//   //     await prefs.setString('userRole', role);

//   //     final fullProfile = await _authService.fetchFullEmployeeProfile(email);

//   //     if (fullProfile != null) {
//   //       // (Your existing code for setting SharedPreferences and Provider...)
//   //       await prefs.setInt('employeeId', fullProfile['EmployeeId']);
//   //       await prefs.setString(
//   //         'userName',
//   //         "${fullProfile["FirstName"]} ${fullProfile["LastName"]}",
//   //       );

//   //       final userProfile = {
//   //         "userId": userId,
//   //         "employeeId": fullProfile["EmployeeId"],
//   //         "firstName": fullProfile["FirstName"] ?? "",
//   //         "middleName": fullProfile["MiddleName"] ?? "",
//   //         "lastName": fullProfile["LastName"] ?? "",
//   //         "gender": fullProfile["Gender"] ?? "",
//   //         "email": fullProfile["Email"] ?? "",
//   //         "mobileNumber": fullProfile["MobileNumber"] ?? "",
//   //         "dateOfBirth": fullProfile["DateOfBirth"] ?? "",
//   //         "street": fullProfile["Street"] ?? "",
//   //         "city": fullProfile["City"] ?? "",
//   //         "state": fullProfile["State"] ?? "",
//   //         "postalCode": fullProfile["PostalCode"] ?? "",
//   //         "country": fullProfile["Country"] ?? "",
//   //         "employmentStatus": fullProfile["EmploymentStatus"] ?? "",
//   //         "jobRole": fullProfile["JobRole"] ?? "",
//   //         "userRole": role, // Use role from exchange response
//   //         "profilePicture": fullProfile["ProfilePicture"] ?? "",
//   //         "bankAccountName": fullProfile["BankAccountName"] ?? "",
//   //         "bankAccountNumber": fullProfile["BankAccountNumber"] ?? "",
//   //         "bankBSB": fullProfile["BankBSB"] ?? "",
//   //         "bankName": fullProfile["BankName"] ?? "",
//   //         "nextOfKins": (fullProfile["NextOfKins"] as List<dynamic>? ?? []),
//   //       };

//   //       Provider.of<UserProvider>(context, listen: false)
//   //           .setUserProfile(userProfile);

//   //       // Initialize FCM and register device token
//   //       final notificationService = NotificationService();
//   //       await notificationService.initializeFCM(
//   //         employeeId: fullProfile["EmployeeId"],
//   //         userTag: "user_${fullProfile["EmployeeId"]}",
//   //       );
//   //     } else {
//   //       _showSnackBar("Could not load full profile data.");
//   //       return;
//   //     }

//   //     // Navigate to the appropriate page based on user role
//   //     print("Navigating based on role: $role"); // Add log for role check
//   //     if (role == "Manager") {
//   //       Navigator.pushReplacement(
//   //         context,
//   //         MaterialPageRoute(
//   //             builder: (context) => const Bottomnavbar(
//   //                   selectedIndex: 0,
//   //                 )),
//   //       );
//   //     } else {
//   //       // Default to employee dashboard if role is not Manager or empty
//   //       Navigator.pushReplacement(
//   //         context,
//   //         MaterialPageRoute(builder: (context) => EmpBottomnavbar()),
//   //       );
//   //     }
//   //   } catch (e) {
//   //     _showSnackBar("Login failed: ${e.toString()}");
//   //     print("Login Error: $e");
//   //   }
//   // }
//   // --- END OF REVERTED FUNCTION ---

//   void _handleEmailPasswordLogin() async {
//     String email = _emailController.text.trim();
//     String password = _passwordController.text.trim();

//     if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
//       _showSnackBar("Please fix the errors in the form.");
//       return;
//     }

//     try {
//       // -----------------------------------------------------------------
//       // STEP 1: Call the LOGIN endpoint
//       // -----------------------------------------------------------------
//       final loginResponse = await _authService.login(email, password);
//       print("Login Response in UI: $loginResponse");

//       // Check for null response
//       if (loginResponse == null) {
//         _showSnackBar(
//             "Unable to connect to the server. Please check your internet.");
//         return;
//       }

//       // --- 🛠️ IMPROVED ERROR HANDLING 🛠️ ---

//       // 1. Check Flags
//       bool isSuccess = loginResponse['message'] == "Login successful" ||
//           loginResponse['message'] ==
//               "Login with temporary password successful";
//       bool isOnboarding = loginResponse["onboardingRequired"] == true;

//       // 2. Handle Errors (If NOT Success AND NOT Onboarding)
//       if (!isSuccess && !isOnboarding) {
//         String backendMsg =
//             loginResponse['message'] ?? loginResponse['Message'] ?? "";

//         // 🎨 User-Friendly Message Translation
//         String userFriendlyMsg = "An unexpected error occurred.";

//         if (backendMsg.contains("Pending")) {
//           userFriendlyMsg =
//               "Your account is currently under review. Please wait for admin approval.";
//         } else if (backendMsg.contains("Invalid credentials") ||
//             backendMsg.contains("401")) {
//           userFriendlyMsg = "Invalid email or password. Please try again.";
//         } else if (backendMsg.contains("User not found")) {
//           userFriendlyMsg = "No account found with this email.";
//         } else if (backendMsg.isNotEmpty) {
//           // Fallback: Clean up "Server Error (403): ..." to just the message part if possible
//           userFriendlyMsg =
//               backendMsg.replaceAll(RegExp(r'Server Error \(\d+\): '), '');
//         }

//         _showSnackBar(userFriendlyMsg);
//         return;
//       }
//       // --- 🛠️ END ERROR HANDLING 🛠️ ---

//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('userEmail', email);
//       print("User Email stored: $email");

//       // -----------------------------------------------------------------
//       // STEP 2: Check ONBOARDING flags
//       // -----------------------------------------------------------------
//       final bool onboardingRequired =
//           loginResponse["onboardingRequired"] ?? false;
//       final String onboardingMode = loginResponse["onboardingMode"] ?? "none";

//       if (onboardingRequired) {
//         print("Onboarding required. Mode: $onboardingMode");

//         Map<String, dynamic>? existingProfile;

//         // 1. EXTRACT ID HERE (So it's available for both fetching and navigation)
//         final int? idToPass =
//             loginResponse["employeeId"] ?? loginResponse["userId"];
//         print("🔹 ID extracted for Onboarding: $idToPass");

//         // Check specifically for resubmission
//         if (onboardingMode == "resubmission") {
//           print("Resubmission mode: Fetching rejected items.");

//           if (idToPass != null && idToPass != 0) {
//             // Use the extracted ID
//             existingProfile =
//                 await _authService.fetchRejectedProfileData(idToPass);

//             if (existingProfile == null) {
//               _showSnackBar(
//                   "Could not load your profile data. Please contact support.");
//               return;
//             }
//           } else {
//             print("Warning: Employee ID is null or 0 during resubmission.");
//           }
//         }

//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(
//             builder: (context) => Emponboard(
//               email: email,
//               existingProfile: existingProfile,
//               // 2. PASS THE ID HERE (This was missing in your code!)
//               employeeId: idToPass,
//             ),
//           ),
//         );
//         return; // Stop execution
//       }

//       // -----------------------------------------------------------------
//       // STEP 3: User is active. Exchange password for a token.
//       // -----------------------------------------------------------------
//       print("User is active. Exchanging password for token.");
//       final exchangeResponse =
//           await _authService.exchangePasswordForToken(email, password);

//       if (exchangeResponse == null || exchangeResponse['appToken'] == null) {
//         _showSnackBar("Authentication failed. Please try again.");
//         return;
//       }

//       print("Token received. Proceeding to fetch profile.");
//       if (exchangeResponse['appToken'] != null) {
//         await prefs.setString('appToken', exchangeResponse['appToken']);
//         print("✅ Token saved to SharedPreferences: appToken");
//       }

//       // -----------------------------------------------------------------
//       // STEP 4: Token is saved. Now fetch profile and navigate.
//       // -----------------------------------------------------------------
//       int? userId = exchangeResponse["userId"];
//       String role = exchangeResponse["userRole"] ?? "Unknown";
//       await prefs.setInt('userId', userId!);
//       await prefs.setString('userRole', role);

//       final fullProfile = await _authService.fetchFullEmployeeProfile(email);

//       if (fullProfile != null) {
//         await prefs.setInt('employeeId', fullProfile['EmployeeId']);
//         await prefs.setString(
//           'userName',
//           "${fullProfile["FirstName"]} ${fullProfile["LastName"]}",
//         );

//         final userProfile = {
//           "userId": userId,
//           "employeeId": fullProfile["EmployeeId"],
//           "firstName": fullProfile["FirstName"] ?? "",
//           "middleName": fullProfile["MiddleName"] ?? "",
//           "lastName": fullProfile["LastName"] ?? "",
//           "gender": fullProfile["Gender"] ?? "",
//           "email": fullProfile["Email"] ?? "",
//           "mobileNumber": fullProfile["MobileNumber"] ?? "",
//           "dateOfBirth": fullProfile["DateOfBirth"] ?? "",
//           "street": fullProfile["Street"] ?? "",
//           "city": fullProfile["City"] ?? "",
//           "state": fullProfile["State"] ?? "",
//           "postalCode": fullProfile["PostalCode"] ?? "",
//           "country": fullProfile["Country"] ?? "",
//           "employmentStatus": fullProfile["EmploymentStatus"] ?? "",
//           "jobRole": fullProfile["JobRole"] ?? "",
//           "userRole": role,
//           "profilePicture": fullProfile["ProfilePicture"] ?? "",
//           "bankAccountName": fullProfile["BankAccountName"] ?? "",
//           "bankAccountNumber": fullProfile["BankAccountNumber"] ?? "",
//           "bankBSB": fullProfile["BankBSB"] ?? "",
//           "bankName": fullProfile["BankName"] ?? "",
//           "nextOfKins": (fullProfile["NextOfKins"] as List<dynamic>? ?? []),
//         };

//         Provider.of<UserProvider>(context, listen: false)
//             .setUserProfile(userProfile);

//         final notificationService = NotificationService();
//         await notificationService.initializeFCM(
//           employeeId: fullProfile["EmployeeId"],
//           userTag: "user_${fullProfile["EmployeeId"]}",
//         );
//       } else {
//         _showSnackBar("Could not load your profile. Please restart the app.");
//         return;
//       }

//       print("Navigating based on role: $role");
//       if (role == "Manager") {
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(
//               builder: (context) => const Bottomnavbar(selectedIndex: 0)),
//         );
//       } else {
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(builder: (context) => EmpBottomnavbar()),
//         );
//       }
//     } catch (e) {
//       _showSnackBar("Login failed. Please check your connection.");
//       print("Login Error: $e");
//     }
//   }

//   void _showSnackBar(String message) {
//     ScaffoldMessenger.of(context)
//         .showSnackBar(SnackBar(content: Text(message)));
//   }

//   // Future<void> _mslogIn() async {
//   //   final success = await _flutterauth.signIn();
//   //   if (success) {
//   //     setState(() {
//   //       userName = _flutterauth.profile?['name'];
//   //       userEmail = _flutterauth.profile?['preferred_username'];
//   //     });
//   //   }
//   // }

//   @override
//   Widget build(BuildContext context) {
//     final size = MediaQuery.of(context).size;
//     final logoSize = size.width * 0.5;
//     final paddingUnit = size.width * 0.03;

//     return Scaffold(
//         backgroundColor: const Color(0xFF2F3846),
//         body: Stack(children: [
//           const Positioned.fill(child: LoginBackground()),
//           SafeArea(
//             child: Center(
//               child: SingleChildScrollView(
//                 padding: EdgeInsets.all(paddingUnit * 2),
//                 child: Form(
//                   key: _formKey,
//                   autovalidateMode: AutovalidateMode.onUserInteraction,
//                   child: Column(
//                     children: [
//                       Image(
//                         image: AssetImage('assets/logo.png'),
//                         width: logoSize,
//                         height: logoSize,
//                       ),
//                       ClipRRect(
//                         borderRadius: BorderRadius.circular(20),
//                         child: BackdropFilter(
//                           filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
//                           child: Container(
//                             padding: const EdgeInsets.all(20),
//                             decoration: BoxDecoration(
//                               color: const Color.fromARGB(136, 42, 41, 41)
//                                   .withOpacity(0.6),
//                               borderRadius: BorderRadius.circular(20),
//                               border: Border.all(color: Colors.white),
//                               boxShadow: [
//                                 BoxShadow(
//                                   color: Colors.black.withOpacity(0.2),
//                                   spreadRadius: 2,
//                                   blurRadius: 8,
//                                   offset: const Offset(0, 4),
//                                 ),
//                               ],
//                             ),
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               children: [
//                                 const Text(
//                                   "Login",
//                                   style: TextStyle(
//                                       fontSize: 28,
//                                       fontWeight: FontWeight.bold,
//                                       color: Colors.white),
//                                 ),
//                                 const SizedBox(height: 20),

//                                 // Email Field
//                                 Column(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     const Text(
//                                       "Email",
//                                       style: TextStyle(
//                                           color: Colors.white, fontSize: 16),
//                                     ),
//                                     const SizedBox(height: 5),
//                                     TextFormField(
//                                       controller: _emailController,
//                                       keyboardType: TextInputType.emailAddress,
//                                       style: const TextStyle(
//                                           color:
//                                               Color.fromARGB(255, 32, 32, 32)),
//                                       decoration: InputDecoration(
//                                         hintText: "username@gmail.com",
//                                         hintStyle:
//                                             const TextStyle(color: Colors.grey),
//                                         filled: true,
//                                         fillColor: const Color.fromARGB(
//                                             255, 255, 255, 255),
//                                         border: OutlineInputBorder(
//                                           borderRadius:
//                                               BorderRadius.circular(12),
//                                         ),
//                                       ),
//                                       validator: (value) {
//                                         if (value == null || value.isEmpty) {
//                                           return 'Please enter an email';
//                                         }
//                                         const emailRegex =
//                                             r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
//                                         if (!RegExp(emailRegex)
//                                             .hasMatch(value)) {
//                                           return 'Please enter a valid email address';
//                                         }
//                                         return null;
//                                       },
//                                     ),
//                                   ],
//                                 ),

//                                 const SizedBox(height: 15),

//                                 // Password Field
//                                 Column(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     const Text(
//                                       "Password",
//                                       style: TextStyle(
//                                           color: Colors.white, fontSize: 16),
//                                     ),
//                                     const SizedBox(height: 5),
//                                     TextFormField(
//                                       controller: _passwordController,
//                                       obscureText: _obscureText,
//                                       style: const TextStyle(
//                                           color:
//                                               Color.fromARGB(255, 17, 17, 17)),
//                                       decoration: InputDecoration(
//                                         hintText: "Password",
//                                         hintStyle:
//                                             const TextStyle(color: Colors.grey),
//                                         filled: true,
//                                         fillColor: const Color.fromARGB(
//                                             255, 255, 255, 255),
//                                         border: OutlineInputBorder(
//                                           borderRadius:
//                                               BorderRadius.circular(12),
//                                         ),
//                                         suffixIcon: IconButton(
//                                           icon: Icon(
//                                             _obscureText
//                                                 ? Icons.visibility_off
//                                                 : Icons.visibility,
//                                             color: Colors.grey,
//                                           ),
//                                           onPressed: () {
//                                             setState(() {
//                                               _obscureText = !_obscureText;
//                                             });
//                                           },
//                                         ),
//                                       ),
//                                       validator: (value) {
//                                         if (value == null || value.isEmpty) {
//                                           return 'Please enter your password';
//                                         }
//                                         return null;
//                                       },
//                                     ),
//                                   ],
//                                 ),

//                                 const SizedBox(height: 10),
//                                 Align(
//                                   alignment: Alignment.centerLeft,
//                                   child: TextButton(
//                                     onPressed: () {
//                                       Navigator.push(
//                                         context,
//                                         MaterialPageRoute(
//                                             builder: (context) =>
//                                                 const ForgotPasswordScreen()),
//                                       );
//                                     },
//                                     child: const Text(
//                                       "Forgot Password?",
//                                       style: TextStyle(color: Colors.white70),
//                                     ),
//                                   ),
//                                 ),
//                                 const SizedBox(height: 15),
//                                 Center(
//                                   child: SizedBox(
//                                     width: size.width * 0.7,
//                                     child: ElevatedButton(
//                                       onPressed: _handleEmailPasswordLogin,
//                                       style: ElevatedButton.styleFrom(
//                                         backgroundColor:
//                                             const Color(0xFF2979FF),
//                                         padding: const EdgeInsets.symmetric(
//                                             vertical: 16, horizontal: 0),
//                                         shape: RoundedRectangleBorder(
//                                           borderRadius:
//                                               BorderRadius.circular(10),
//                                         ),
//                                       ),
//                                       child: const Text(
//                                         "Log In",
//                                         style: TextStyle(
//                                             fontSize: 16, color: Colors.white),
//                                       ),
//                                     ),
//                                   ),
//                                 ),
//                                 const SizedBox(
//                                   height: 15,
//                                 ),

//                                 const Row(
//                                   children: [
//                                     Expanded(
//                                       child: Divider(
//                                         color: Colors.white38,
//                                         thickness: 1,
//                                       ),
//                                     ),
//                                     Padding(
//                                       padding:
//                                           EdgeInsets.symmetric(horizontal: 8.0),
//                                       child: Text(
//                                         "Or Sign In With",
//                                         style: TextStyle(color: Colors.white),
//                                       ),
//                                     ),
//                                     Expanded(
//                                       child: Divider(
//                                         color: Colors.white38,
//                                         thickness: 1,
//                                       ),
//                                     ),
//                                   ],
//                                 ),

//                                 const SizedBox(height: 20),

//                                 // Social Buttons
//                                 Center(
//                                   child: SizedBox(
//                                     width: size.width * 0.8,
//                                     child: Row(
//                                       mainAxisAlignment:
//                                           MainAxisAlignment.spaceEvenly,
//                                       children: [
//                                         Expanded(
//                                           child: ElevatedButton.icon(
//                                             onPressed: () {
//                                               // Navigator.pushReplacement(
//                                               //   context,
//                                               //   MaterialPageRoute(
//                                               //       builder: (context) =>
//                                               //           const Emponboard()),
//                                               // );
//                                             },
//                                             icon: Image.network(
//                                               'https://img.icons8.com/?size=100&id=17949&format=png&color=000000',
//                                               height: 24,
//                                               width: 24,
//                                             ),
//                                             label: const Text("Google"),
//                                             style: ElevatedButton.styleFrom(
//                                               backgroundColor: Colors.white,
//                                               foregroundColor: Colors.black,
//                                               padding:
//                                                   const EdgeInsets.symmetric(
//                                                       horizontal: 16,
//                                                       vertical: 12),
//                                               shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(
//                                                           20)),
//                                             ),
//                                           ),
//                                         ),
//                                         const SizedBox(width: 16),
//                                         Expanded(
//                                           child: ElevatedButton.icon(
//                                             onPressed: () {
//                                               // _mslogIn();
//                                             },
//                                             icon: Image.network(
//                                               'https://img.icons8.com/?size=100&id=22989&format=png&color=000000',
//                                               height: 24,
//                                               width: 24,
//                                             ),
//                                             label: const Text("Microsoft"),
//                                             style: ElevatedButton.styleFrom(
//                                               backgroundColor: Colors.white,
//                                               foregroundColor: Colors.black,
//                                               padding:
//                                                   const EdgeInsets.symmetric(
//                                                       horizontal: 16,
//                                                       vertical: 12),
//                                               shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(
//                                                           20)),
//                                             ),
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ]));
//   }
// } // End of _LoginState class






// lib/screens/login.dart


// import 'dart:ui';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:shiftsmart/providers/user_provider.dart';
// import 'package:shiftsmart/screens/employee/empOnboard.dart';
// import 'package:shiftsmart/screens/forgot_password.dart';
// import 'package:shiftsmart/services/auth_service.dart';
// import 'package:shiftsmart/services/notification_service.dart';
// import 'package:shiftsmart/utils/fullscreen_helper.dart';
// import 'package:shiftsmart/widgets/bottomnavbar.dart';
// import 'package:shiftsmart/widgets/emp_bottomnavbar.dart';
// import 'package:shiftsmart/widgets/loginBackground.dart';

// class Login extends StatefulWidget {
//   const Login({super.key});

//   @override
//   State<Login> createState() => _LoginState();
// }

// class _LoginState extends State<Login> {
//   final AuthService _authService = AuthService();

//   // Controllers
//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _passwordController = TextEditingController();

//   // State
//   bool _obscureText = true;
//   bool _isLoading = false;                                // ← ADDED THIS LINE
//   final _formKey = GlobalKey<FormState>();

//   @override
//   void initState() {
//     super.initState();
//     disableFullScreen();
//   }

//   // Main Login Logic
//   void _handleEmailPasswordLogin() async {
//     String email = _emailController.text.trim();
//     String password = _passwordController.text.trim();

//     if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
//       _showSnackBar("Please fix the errors in the form.");
//       return;
//     }

//     // Set loading state to true                            // ← ADDED THIS LINE
//     setState(() {
//       _isLoading = true;
//     });

//     // Show loading indicator
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => const Center(child: CircularProgressIndicator()),
//     );

//     try {
//       // 1. Call Login Endpoint
//       final loginResponse = await _authService.login(email, password);

//       // Remove loading indicator
//       Navigator.of(context).pop();

//       if (loginResponse == null) {
//         _showSnackBar("Unable to connect to server.");
//         return;
//       }

//       // 2. Error Handling
//       bool isSuccess = loginResponse['message'] == "Login successful" ||
//           loginResponse['message'] ==
//               "Login with temporary password successful";
//       bool isOnboarding = loginResponse["onboardingRequired"] == true;

//       if (!isSuccess && !isOnboarding) {
//         String backendMsg =
//             loginResponse['message'] ?? "An unexpected error occurred.";
//         _showSnackBar(backendMsg);
//         return;
//       }

//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('userEmail', email);

//       // 3. Handle Onboarding / Resubmission
//       if (isOnboarding) {
//         final int? idToPass =
//             loginResponse["employeeId"] ?? loginResponse["userId"];
//         final String onboardingMode = loginResponse["onboardingMode"] ?? "none";
//         Map<String, dynamic>? existingProfile;

//         if (onboardingMode == "resubmission" && idToPass != null) {
//           existingProfile =
//               await _authService.fetchRejectedProfileData(idToPass);
//         }

//         if (mounted) {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(
//               builder: (context) => Emponboard(
//                 email: email,
//                 existingProfile: existingProfile,
//                 employeeId: idToPass,
//               ),
//             ),
//           );
//         }
//         return;
//       }

//       // 4. Exchange Password for Token
//       final exchangeResponse =
//           await _authService.exchangePasswordForToken(email, password);

//       if (exchangeResponse == null || exchangeResponse['appToken'] == null) {
//         _showSnackBar("Authentication failed.");
//         return;
//       }

//       // CRITICAL: Save Token BEFORE initializing FCM registration
//       await prefs.setString('appToken', exchangeResponse['appToken']);
//       print("Token saved successfully.");

//       // 5. Fetch Full Profile
//       int? userId = exchangeResponse["userId"];
//       String role = exchangeResponse["userRole"] ?? "Employee";
//       await prefs.setInt('userId', userId!);
//       await prefs.setString('userRole', role);

//       final fullProfile = await _authService.fetchFullEmployeeProfile(email);

//       if (fullProfile != null) {
//         await prefs.setInt('employeeId', fullProfile['EmployeeId']);
//         await prefs.setString(
//           'userName',
//           "${fullProfile["FirstName"]} ${fullProfile["LastName"]}",
//         );

//         // Update Provider
//         final userProfile = {
//           "userId": userId,
//           "employeeId": fullProfile["EmployeeId"],
//           "firstName": fullProfile["FirstName"] ?? "",
//           "middleName": fullProfile["MiddleName"] ?? "",
//           "lastName": fullProfile["LastName"] ?? "",
//           "gender": fullProfile["Gender"] ?? "",
//           "email": fullProfile["Email"] ?? "",
//           "mobileNumber": fullProfile["MobileNumber"] ?? "",
//           "dateOfBirth": fullProfile["DateOfBirth"] ?? "",
//           "street": fullProfile["Street"] ?? "",
//           "city": fullProfile["City"] ?? "",
//           "state": fullProfile["State"] ?? "",
//           "postalCode": fullProfile["PostalCode"] ?? "",
//           "country": fullProfile["Country"] ?? "",
//           "employmentStatus": fullProfile["EmploymentStatus"] ?? "",
//           "jobRole": fullProfile["JobRole"] ?? "",
//           "userRole": role,
//           "profilePicture": fullProfile["ProfilePicture"] ?? "",
//           "bankAccountName": fullProfile["BankAccountName"] ?? "",
//           "bankAccountNumber": fullProfile["BankAccountNumber"] ?? "",
//           "bankBSB": fullProfile["BankBSB"] ?? "",
//           "bankName": fullProfile["BankName"] ?? "",
//           "nextOfKins": (fullProfile["NextOfKins"] as List<dynamic>? ?? []),
//         };

//         if (mounted) {
//           Provider.of<UserProvider>(context, listen: false)
//               .setUserProfile(userProfile);
//         }

//         // Enable Push Notifications
//         try {
//           print("Initializing FCM for User: ${fullProfile["EmployeeId"]}");
//           final notificationService = NotificationService();
//           // Since we are logged in, we pass the real EmployeeId.
//           // Because ID != 0, it will proceed to register with the backend using the saved AppToken.
//           await notificationService.initializeFCM(
//             employeeId: fullProfile["EmployeeId"],
//             userTag: "user_${fullProfile["EmployeeId"]}",
//           );
//           final fcmToken = await FirebaseMessaging.instance.getToken();
//           print("MY FCM TOKEN: $fcmToken");
//         } catch (fcmError) {
//           print("FCM Init Warning: $fcmError");
//         }
//       } else {
//         _showSnackBar("Could not load profile.");
//         return;
//       }

//       // 6. Navigation
//       if (mounted) {
//         if (role == "Manager") {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(
//                 builder: (context) => const Bottomnavbar(selectedIndex: 0)),
//           );
//         } else {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(builder: (context) => const EmpBottomnavbar()),
//           );
//         }
//       }
//     } catch (e) {
//       _showSnackBar("Login Error: $e");
//       print("Login Exception: $e");
//     }
//   }

//   void _showSnackBar(String message) {
//     if (mounted) {
//       ScaffoldMessenger.of(context)
//           .showSnackBar(SnackBar(content: Text(message)));
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final size = MediaQuery.of(context).size;
//     final logoSize = size.width * 0.5;
//     final paddingUnit = size.width * 0.03;

//     return Scaffold(
//         backgroundColor: const Color(0xFF2F3846),
//         body: Stack(children: [
//           const Positioned.fill(child: LoginBackground()),
//           SafeArea(
//             child: Center(
//               child: SingleChildScrollView(
//                 padding: EdgeInsets.all(paddingUnit * 2),
//                 child: Form(
//                   key: _formKey,
//                   autovalidateMode: AutovalidateMode.onUserInteraction,
//                   child: Column(
//                     children: [
//                       Image(
//                         image: const AssetImage('assets/logo.png'),
//                         width: logoSize,
//                         height: logoSize,
//                       ),
//                       ClipRRect(
//                         borderRadius: BorderRadius.circular(20),
//                         child: BackdropFilter(
//                           filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
//                           child: Container(
//                             padding: const EdgeInsets.all(20),
//                             decoration: BoxDecoration(
//                               color: const Color.fromARGB(136, 42, 41, 41)
//                                   .withOpacity(0.6),
//                               borderRadius: BorderRadius.circular(20),
//                               border: Border.all(color: Colors.white),
//                               boxShadow: [
//                                 BoxShadow(
//                                   color: Colors.black.withOpacity(0.2),
//                                   spreadRadius: 2,
//                                   blurRadius: 8,
//                                   offset: const Offset(0, 4),
//                                 ),
//                               ],
//                             ),
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               children: [
//                                 const Text(
//                                   "Login",
//                                   style: TextStyle(
//                                       fontSize: 28,
//                                       fontWeight: FontWeight.bold,
//                                       color: Colors.white),
//                                 ),
//                                 const SizedBox(height: 20),
//                                 // Email Field
//                                 const Text("Email",
//                                     style: TextStyle(
//                                         color: Colors.white, fontSize: 16)),
//                                 const SizedBox(height: 5),
//                                 TextFormField(
//                                   controller: _emailController,
//                                   keyboardType: TextInputType.emailAddress,
//                                   style: const TextStyle(
//                                       color: Color.fromARGB(255, 32, 32, 32)),
//                                   decoration: InputDecoration(
//                                     hintText: "username@gmail.com",
//                                     hintStyle:
//                                         const TextStyle(color: Colors.grey),
//                                     filled: true,
//                                     fillColor: const Color.fromARGB(
//                                         255, 255, 255, 255),
//                                     border: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12)),
//                                   ),
//                                   validator: (value) {
//                                     if (value == null || value.isEmpty)
//                                       return 'Please enter an email';
//                                     const emailRegex =
//                                         r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
//                                     if (!RegExp(emailRegex).hasMatch(value))
//                                       return 'Please enter a valid email address';
//                                     return null;
//                                   },
//                                 ),
//                                 const SizedBox(height: 15),
//                                 // Password Field
//                                 const Text("Password",
//                                     style: TextStyle(
//                                         color: Colors.white, fontSize: 16)),
//                                 const SizedBox(height: 5),
//                                 TextFormField(
//                                   controller: _passwordController,
//                                   obscureText: _obscureText,
//                                   style: const TextStyle(
//                                       color: Color.fromARGB(255, 17, 17, 17)),
//                                   decoration: InputDecoration(
//                                     hintText: "Password",
//                                     hintStyle:
//                                         const TextStyle(color: Colors.grey),
//                                     filled: true,
//                                     fillColor: const Color.fromARGB(
//                                         255, 255, 255, 255),
//                                     border: OutlineInputBorder(
//                                         borderRadius:
//                                             BorderRadius.circular(12)),
//                                     suffixIcon: IconButton(
//                                       icon: Icon(
//                                         _obscureText
//                                             ? Icons.visibility_off
//                                             : Icons.visibility,
//                                         color: Colors.grey,
//                                       ),
//                                       onPressed: () => setState(
//                                           () => _obscureText = !_obscureText),
//                                     ),
//                                   ),
//                                   validator: (value) {
//                                     if (value == null || value.isEmpty)
//                                       return 'Please enter your password';
//                                     return null;
//                                   },
//                                 ),
//                                 const SizedBox(height: 10),
//                                 Align(
//                                   alignment: Alignment.centerLeft,
//                                   child: TextButton(
//                                     onPressed: () {
//                                       Navigator.push(
//                                         context,
//                                         MaterialPageRoute(
//                                             builder: (context) =>
//                                                 const ForgotPasswordScreen()),
//                                       );
//                                     },
//                                     child: const Text("Forgot Password?",
//                                         style:
//                                             TextStyle(color: Colors.white70)),
//                                   ),
//                                 ),
//                                 const SizedBox(height: 15),
//                                 Center(
//                                   child: SizedBox(
//                                     width: size.width * 0.7,
//                                     child: ElevatedButton(
//                                       //onPressed: _handleEmailPasswordLogin,
//                                       onPressed: _isLoading ? null : _handleEmailPasswordLogin,
//                                       style: ElevatedButton.styleFrom(
//                                         backgroundColor:
//                                             _isLoading ? Colors.grey : const Color(0xFF2979FF),
//                                             //const Color(0xFF2979FF),
//                                         padding: const EdgeInsets.symmetric(
//                                             vertical: 16, horizontal: 0),
//                                         shape: RoundedRectangleBorder(
//                                             borderRadius:
//                                                 BorderRadius.circular(10)),
//                                       ),
//                                       child: const Text("Log In",
//                                           style: TextStyle(
//                                               fontSize: 16,
//                                               color: Colors.white)),
//                                     ),
//                                   ),
//                                 ),
//                                 const SizedBox(height: 15),

//                                 const Row(
//                                   children: [
//                                     Expanded(
//                                         child: Divider(
//                                             color: Colors.white38,
//                                             thickness: 1)),
//                                     Padding(
//                                       padding:
//                                           EdgeInsets.symmetric(horizontal: 8.0),
//                                       child: Text("Or Sign In With",
//                                           style:
//                                               TextStyle(color: Colors.white)),
//                                     ),
//                                     Expanded(
//                                         child: Divider(
//                                             color: Colors.white38,
//                                             thickness: 1)),
//                                   ],
//                                 ),
//                                 const SizedBox(height: 20),

//                                 // Social Buttons (Placeholders)
//                                 Center(
//                                   child: SizedBox(
//                                     width: size.width * 0.8,
//                                     child: Row(
//                                       mainAxisAlignment:
//                                           MainAxisAlignment.spaceEvenly,
//                                       children: [
//                                         Expanded(
//                                           child: ElevatedButton.icon(
//                                             onPressed: () {},
//                                             icon: Image.network(
//                                               'https://img.icons8.com/?size=100&id=17949&format=png&color=000000',
//                                               height: 24,
//                                               width: 24,
//                                             ),
//                                             label: const Text("Google"),
//                                             style: ElevatedButton.styleFrom(
//                                               backgroundColor: Colors.white,
//                                               foregroundColor: Colors.black,
//                                               padding:
//                                                   const EdgeInsets.symmetric(
//                                                       horizontal: 16,
//                                                       vertical: 12),
//                                               shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(
//                                                           20)),
//                                             ),
//                                           ),
//                                         ),
//                                         const SizedBox(width: 16),
//                                         Expanded(
//                                           child: ElevatedButton.icon(
//                                             onPressed: () {},
//                                             icon: Image.network(
//                                               'https://img.icons8.com/?size=100&id=22989&format=png&color=000000',
//                                               height: 24,
//                                               width: 24,
//                                             ),
//                                             label: const Text("Microsoft"),
//                                             style: ElevatedButton.styleFrom(
//                                               backgroundColor: Colors.white,
//                                               foregroundColor: Colors.black,
//                                               padding:
//                                                   const EdgeInsets.symmetric(
//                                                       horizontal: 16,
//                                                       vertical: 12),
//                                               shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(
//                                                           20)),
//                                             ),
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ]));
//   }
// }
