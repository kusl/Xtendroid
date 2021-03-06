package org.xtendroid.content.res

import android.content.res.Resources
import android.content.Context
import java.text.DateFormat
import java.text.MessageFormat
import java.text.NumberFormat
import java.util.Date
import org.eclipse.xtend.lib.macro.Active
import org.eclipse.xtend.lib.macro.TransformationContext
import org.eclipse.xtend.lib.macro.declaration.MutableClassDeclaration
import org.eclipse.xtend.lib.macro.declaration.Visibility
import org.xtendroid.utils.NamingUtils

import java.lang.annotation.ElementType
import java.lang.annotation.Target
import java.util.List
import org.eclipse.xtend.lib.macro.declaration.MutableMemberDeclaration
import org.eclipse.xtend.lib.macro.TransformationParticipant
import org.eclipse.xtend.lib.macro.declaration.FieldDeclaration
import org.eclipse.xtend.lib.macro.declaration.MutableFieldDeclaration

import static extension org.xtendroid.utils.XmlUtils.*
import org.eclipse.xtend.lib.macro.RegisterGlobalsParticipant
import org.eclipse.xtend.lib.macro.RegisterGlobalsContext

/*
 * An annotation that generates accessor methods to Android string resources.
 * 
 * <p>It uses java's @link{java.text.MessageFormat} in the values and the accessor methods will sport typed parameters according to the placeholders.
 * For example, given a strings.xml like this : </p>
 * <code>
 *    &lt;string name="my_key"&gt;Hello {0}, today is {1,date}&lt;/string&gt;
 * </code>
 * <p>Will result in a method signature:</p>
 * <code>
 *   def String getMyKey(String arg1, Date arg2) {...} 
 * </code>
 */
@Active(AndroidResourcesProcessor)
@Target(value=#[ElementType.FIELD, ElementType.TYPE])
annotation AndroidResources {
    Class<?> type = Object // e.g. R.string, R.integer, R.boolean
    String path = "build/intermediates/res/merged/debug/values/values.xml" // where everything is merged together
}

class AndroidResourcesProcessor implements TransformationParticipant<MutableMemberDeclaration>, RegisterGlobalsParticipant {


    /**
     *
     * Transform a pojo class to support getters for resources
     *
     */
    def dispatch void transform(MutableClassDeclaration annotatedClass, extension TransformationContext context) {
      val resourcesType = Resources.newTypeReference
      if (annotatedClass.findDeclaredMethod("getResources", resourcesType) == null) {
         annotatedClass.addMethod('getResources') [
            returnType = resourcesType
            visibility = Visibility.PROTECTED
            abstract = true
         ]
         annotatedClass.abstract = true
      }

      // Does this work with new style android gradle default file structure?
      // This should be parameterizable, to support something like:
      // ./XtendroidTest/build/intermediates/res/merged/debug/values/values.xml,
      // because everything is merged here, and there is no guarantee that strings are stored in strings.xml
      // these could be placed into e.g. strings1.xml, strings2.xml, moar-strings.xml, tanga.xml
      // also there are no guarantees that these will be put into res/values either e.g.
      // res/values-<language>-<resolution>-<blah> are also valid locations
      val stringsPath = annotatedClass.compilationUnit.filePath.projectFolder.append("res/values/strings.xml")
      if (stringsPath.exists) {
         stringsPath.contentsAsStream.document.traverseAllNodes [
            if (nodeName == 'string') {
               val name = getAttribute('name')
               val value = firstChild.nodeValue
               val msgFormat = try {
                  new MessageFormat(value)
               } catch (IllegalArgumentException e) {
                  annotatedClass.annotations.head.addError(
                     "Invalid message format in '" + stringsPath + "'. Value for '" + name + "' is invalid.: " +
                        e.message)
                  new MessageFormat("")
               }
               val formats = msgFormat.formatsByArgumentIndex

               annotatedClass.addMethod("get" + NamingUtils.toJavaIdentifier(name).toFirstUpper) [
                  returnType = string
                  formats.forEach [ format, idx |
                     addParameter("arg" + idx,
                        switch format {
                           NumberFormat: primitiveInt
                           DateFormat: Date.newTypeReference()
                           default: string
                        })
                  ]
                  docComment = "Default value : '"+value+"'"
                  if (formats.empty) {
                     body = [
                        '''
                           return this.getResources().getString(R.string.«name»);
                        ''']
                  } else {
                     val params = parameters
                     body = [
                        '''
                           return «toJavaCode(MessageFormat.newTypeReference)».format(this.getResources().getString(R.string.«name»),«params.map[simpleName].join(',')»);
                        ''']
                  }
               ]
            }
         ]
      }

   }

    val mapResourceTypeToGetMethod = #{
        'R.string' -> 'getString'
        , 'R.color' -> 'getColor'
        , 'R.dimen' -> 'getDimension'
        , 'R.bool' -> 'getBoolean' // TODO see also getBooleanArray... or something
        , 'R.integer' -> 'getInteger'
        //, 'R.fraction' -> 'getFraction' // tricky bugger
    }

    val mapResourceTypeToReturnType = #{
        'R.string' -> String
        , 'R.color' -> Integer
        , 'R.dimen' -> Float
        , 'R.bool' -> Boolean // TODO see also getBooleanArray... or something
        , 'R.integer' -> Integer
        //, 'R.fraction' -> '?' // tricky bugger
    }

    val mapAggregateResourceTypeReturnType = #{
        'integer-array' -> typeof(int) //.newTypeReference.newArrayTypeReference
        , 'string-array' -> typeof(String) //.newTypeReference.newArrayTypeReference
    }

    val mapAggregateResourceTypeToGetMethod = #{
        'integer-array' -> 'getIntArray'
        , 'string-array' -> 'getStringArray'
    }

    def parseXmlAndGenerateGetters (MutableClassDeclaration annotatedClass, String xmlPath, String resourceTypeName, extension TransformationContext context)
    {
        val xmlSource = annotatedClass.compilationUnit.filePath.projectFolder.append(xmlPath)

        if (!xmlSource.exists) {
            annotatedClass.addError(String.format("The xml %s path does not exist", xmlPath)) // TODO throw exception, catch it in the calling method?
            return // get out
        }

        if (!resourceTypeName.startsWith('R.')) {
            annotatedClass.addError('The resource type must start with R. (e.g. R.string, R.integer etc.)')
        }
        val resourceNodeName = resourceTypeName.replaceFirst("R.", '')

        // import package.R
        val resourceType = resourceTypeName.findTypeGlobally.newTypeReference

        // actually only <integer-array /> and <string-array /> are supported
        val aggregateResourceNodeName = resourceNodeName + '-array'

        xmlSource.contentsAsStream.document.traverseAllNodes [
            if (nodeName == resourceNodeName) {
                val name = getAttribute('name')
                annotatedClass.addMethod("get" + NamingUtils.toJavaIdentifier(name).toFirstUpper) [
                    returnType = mapResourceTypeToReturnType.get(resourceTypeName).newTypeReference
                    body = [
                        '''
                        if (mResources == null)
                        {
                            mResources = mContext.getResources();
                        }
                        return mResources.«mapResourceTypeToGetMethod.get(resourceTypeName)»(«toJavaCode(resourceType)».«name»);
                        '''
                    ]
                ]
            }

            // actually only <integer-array /> and <string-array /> are supported
            if (nodeName == aggregateResourceNodeName) {
                val name = getAttribute('name')
                annotatedClass.addMethod("get" + NamingUtils.toJavaIdentifier(name).toFirstUpper) [
                    returnType = mapAggregateResourceTypeReturnType.get(aggregateResourceNodeName).newTypeReference.newArrayTypeReference
                    body = [
                        '''
                        if (mResources == null)
                        {
                            mResources = mContext.getResources();
                        }
                        return mResources.«mapAggregateResourceTypeToGetMethod.get(aggregateResourceNodeName)»(R.array.«name»);
                        '''
                    ]
                ]
            }
        ]
    }

    /*

    Usage:

    1. Apply to any type (Activity, Fragment, View, Poxo) type pray you don't have a name collision
    2. Apply to a member variable

    */

    val androidResourcesString = "AndroidResources"
    def dispatch void transform(MutableFieldDeclaration field, extension TransformationContext context) {

        val annotation = field.annotations.findFirst[ androidResourcesString.equals(annotationTypeDeclaration.simpleName) ]

        // determine the resource type
        val resourceTypeName = annotation.getExpression("type").toString

        // field name == resource class name
        val resourceHelperClassName = field.packageNameFromField + field.simpleName.toFirstUpper
        val resourceHelperClass = context.findClass(resourceHelperClassName)

        // DIY if you want android.R (this is merged eventually), choose your xml path wisely
        if (resourceTypeName.contains('drawable'))
        {
            // TODO file based, not xml, als Resource#getDrawable/1 is deprecated from api level 22 onwards
        }else
        {
            parseXmlAndGenerateGetters(resourceHelperClass, annotation.getStringValue('path'), resourceTypeName, context)
        }

        // determine that host class is an Activity, Fragment, Pojc
        // then adapt the Context#getResources injection method
        // where to get the inflater
        resourceHelperClass.addField("mContext") [
            visibility = Visibility.PRIVATE
            type = Context.newTypeReference
            final = true
        ]

        resourceHelperClass.addField("mResources") [
            visibility = Visibility.PRIVATE
            type = Resources.newTypeReference
        ]

        resourceHelperClass.addConstructor [
            visibility = Visibility::PUBLIC
            body = [
                '''
                    this.mContext = context;
				''']
            addParameter("context", Context.newTypeReference)
        ]

        /*
        if (field...extendedClass.equals(Context.newTypeReference) {
            field.initializer = '''new «field.simpleName.toFirstUpper»(this)''' // TODO when instantiating in an Activity or Service
        }else if (field...extendedClass.equals(android.app.Fragment.newTypeReference)) { // api level >=11, TODO also add supportlib support
        {
            field.initializer = '''new «field.simpleName.toFirstUpper»(getActivity())''' // TODO when instantiating in a fragment
        }else if (field...extendedClass.equals(	android.view.View.newTypeReference)) {
        {
            field.initializer = '''new «field.simpleName.toFirstUpper»(mContext)''' // TODO when instantiating in a custom view
        }else
        {
            clazz.addWarning("Currently the use-case beyond Activity/Service/View is out-of-scope.")
            return // get out, you're on your own
        }
        */

        // instantiate resource helper object
        field.initializer = '''new «field.simpleName.toFirstUpper»(this)''' // TODO see the code block above, right now we only support Activity
        field.type = resourceHelperClass.newTypeReference
        field.final = true
    }

    override doTransform(List<? extends MutableMemberDeclaration> list, TransformationContext context) {
        list.forEach[ transform(context) ]
    }

    /**
     *
     * Create a new type based on the R.<type>
     *
     * This must hold: assertTrue(field.simpleName.equals(field.declaringType.simpleName))
     *
     */
    override doRegisterGlobals(List list, RegisterGlobalsContext context) {

        for (m : list)
        {
            try {
                val field = m as FieldDeclaration

                // assertTrue(field.simpleName.equals(field.declaringType.simpleName))
                // because field doesn't have a type yet during this pass
                val fullClassName = field.packageNameFromField + field.simpleName.toFirstUpper
                if (context.findSourceClass(fullClassName) == null)
                {
                    // register only once, this assumption holds unless you sneakily change e.g. values.xml
                    // mid-transpilation
                    context.registerClass(fullClassName)
                }
            } catch (ClassCastException ex) { /* continue */ }
        }
    }

    // TODO remove duplicate in EnumProperty
    def dispatch getPackageNameFromField(FieldDeclaration field) {
        val fieldTypeSimpleName = field.declaringType.simpleName
        val fieldTypeName = field.declaringType.qualifiedName
        val package = fieldTypeName.replace(fieldTypeSimpleName, '')
        package
    }


}
