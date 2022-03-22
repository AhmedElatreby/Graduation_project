import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({Key? key}) : super(key: key);

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
            decoration: const BoxDecoration(
              image: DecorationImage(
                  image: AssetImage(
                      "assests/images/signup.png"
                  ),
                  fit: BoxFit.cover
              ),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: height*0.18,
                ),
                const CircleAvatar(
                  backgroundColor: Colors.white38,
                  radius: 40,
                  backgroundImage: const AssetImage(
                      "assests/images/profile1.png"
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height:70,),
          Container(
            width: width,
            margin: const EdgeInsets.only(left: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome",
                  style: TextStyle(
                      fontSize: 36,
                      fontWeight:  FontWeight.bold,
                      color:Colors.black54

                  ),
                ),
                Text(
                  "a@a.com",
                  style: TextStyle(
                      fontSize: 18,
                      color:Colors.grey

                  ),
                ),
              ],
            ),
          ),
          SizedBox(height:200,),
          Container(
            width: width*0.4,
            height: height*0.07,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              image: const DecorationImage(
                  image: AssetImage(
                      "assests/images/loginbtn.png"
                  ),
                  fit: BoxFit.cover
              ),
            ),
            child: const Center(
              child: Text("Sign out",
                style: TextStyle(
                  fontSize:30,
                  fontWeight: FontWeight.bold,
                  color:Colors.white,
                ),
              ),
            ),

          ),
       ],
      ),
    );

  }
}
