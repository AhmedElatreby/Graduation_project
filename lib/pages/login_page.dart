import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:safetyproject/pages/signup_page.dart';

class LogingPage extends StatefulWidget {
  @override
  _LogingPageState createState() => _LogingPageState();
}

class _LogingPageState extends State<LogingPage> {
  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: width,
            height: height*0.3,
            decoration: BoxDecoration(
              image: const DecorationImage(
                  image: AssetImage(
                      "assests/images/loginimg.png"
                  ),
                  fit: BoxFit.cover
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 20, right: 20),
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Hello",
                  style: TextStyle(
                      fontSize:50,
                      fontWeight: FontWeight.bold
                  ),
                ),
                Text("Sign into your account",
                  style: const TextStyle(
                      fontSize:20,
                      color:Colors.grey
                  ),
                ),
                const SizedBox(height: 30,),
                Container(
                  decoration: BoxDecoration(
                      color:Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                            blurRadius: 10,
                            spreadRadius: 6,
                            offset: Offset(1, 1),
                            color: Colors.grey.withOpacity(0.2)
                        ),
                      ]
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Email",
                      prefixIcon: const Icon(Icons.email, color:Colors.deepOrangeAccent),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: Colors.white,
                            width: 1.0,
                          )
                      ),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                              color: Colors.white,
                              width: 1.0
                          )
                      ),

                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30)
                      ),
                    ),
                  ),
                ),
                const SizedBox(height:15),
                Container(
                  decoration: BoxDecoration(
                      color:Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                            blurRadius: 10,
                            spreadRadius: 7,
                            offset: Offset(1, 1),
                            color: Colors.grey.withOpacity(0.2)
                        ),
                      ]
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Password",
                      prefixIcon: const Icon(Icons.password, color:Colors.deepOrangeAccent),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: Colors.white,
                            width: 1.0,
                          )
                      ),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                              color: Colors.white,
                              width: 1.0
                          )
                      ),

                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30)
                      ),
                    ),
                  ),
                ),
                const SizedBox(height:15),
                Row(
                  children: [
                    Expanded(child: Container(),),
                    Text("Forgot your Password?",
                      style: const TextStyle(
                          fontSize:20,
                          color:Colors.grey
                      ),
                    ),

                  ],
                ),


              ],
            ),
          ),
          SizedBox(height:width*0.08,),
          Container(
            width: width*0.4,
            height: height*0.06,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              image: const DecorationImage(
                  image: AssetImage(
                      "assests/images/loginbtn.png"
                  ),
                  fit: BoxFit.cover
              ),
            ),
            child: Center(
              child: Text("Sign in",
                style: const TextStyle(
                  fontSize:30,
                  fontWeight: FontWeight.bold,
                  color:Colors.white,
                ),
              ),
            ),

          ),
          SizedBox(height: width*0.2,),
          RichText(text: TextSpan(text:"Don\'t have an account?",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 20,
              ),
              children: [
                TextSpan(
                    text:"  Create",
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold
                    ),
                    recognizer: TapGestureRecognizer()..onTap=()=>Get.to(()=>const SignUpPage())
                )
              ]
          )
          )
        ],
      ),
    );
  }
}

